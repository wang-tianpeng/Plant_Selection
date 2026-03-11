import os
import json
import re 
import pandas as pd
from concurrent.futures import ThreadPoolExecutor, as_completed

from crewai import Crew
from crewai_agents import extractor_agent, verifier_agent
from crewai_tasks import build_combined_extraction_task, build_verification_task
from crewai_schema import FIELDS
from crewai_validator import validate_field
from crewai_utils import run_crew, log_info, log_error, clean_json
from crewai_config import MAX_WORKERS, MAX_CHARS


PAPER_DIR = "papers"


def normalize_text(text):
    if not isinstance(text, str):
        return str(text)
    
    replacements = {
        # Dashes (En-dash, Em-dash, etc.) -> Hyphen
        r'[\u2010\u2011\u2012\u2013\u2014\u2015]': '-',
        # Smart Single Quotes -> Straight Quote
        r'[\u2018\u2019\u201a\u201b\u00b4]': "'",
        # Smart Double Quotes -> Straight Quote
        r'[\u201c\u201d\u201e\u201f]': '"',
        # Non-breaking spaces -> Space
        r'[\u00a0\u200b\u3000]': ' ',
        # Bullet points -> Asterisk
        r'[\u2022\u2023\u25e6]': '*'
    }
    
    for pattern, repl in replacements.items():
        text = re.sub(pattern, repl, text)
    return text.strip()


def process_paper(filepath):
    # READ FILE
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            raw_content = f.read()

            paper_text = normalize_text(raw_content)
    except Exception as e:
        log_error(f"Failed to read file {filepath}: {e}")
        return None, None

    paper_text = paper_text[:MAX_CHARS]
    # Handle both extensions
    paper_id = os.path.basename(filepath).replace(".txt", "").replace(".md", "")

    log_info(f"Processing {paper_id}")

    # =========================================================================
    # 1️ Step 1: Combined Extraction + Evidence Gathering
    # =========================================================================
    # usage: One agent extracts structured data AND quotes the text simultaneously
    extract_task = build_combined_extraction_task(extractor_agent, paper_text)
    
    extraction_crew = Crew(
        agents=[extractor_agent],
        tasks=[extract_task],
        verbose=False
    )

    raw_output = run_crew(extraction_crew)
    raw_text = str(raw_output.raw) if hasattr(raw_output, 'raw') else str(raw_output)

    try:
        cleaned_text = clean_json(raw_text)
        if not cleaned_text:
             raise ValueError("Empty output after cleaning")
        

        try:
            extraction_json = json.loads(cleaned_text)
        except json.JSONDecodeError:

            from json_repair import repair_json
            extraction_json = json.loads(repair_json(cleaned_text))
            
    except Exception as e:
        log_error(f"{paper_id} Extraction JSON parse failed: {e}. Raw snippet: {raw_text[:100]}...")
        return None, None

    # =========================================================================
    # 2️ Step 2: Verification
    # =========================================================================
    # usage: Verifier checks the logic/consistency of the extracted value vs evidence
    verify_task = build_verification_task(verifier_agent, extraction_json)

    verification_crew = Crew(
        agents=[verifier_agent],
        tasks=[verify_task],
        verbose=False
    )

    verify_output = run_crew(verification_crew)
    raw_verify_text = str(verify_output.raw) if hasattr(verify_output, 'raw') else str(verify_output)
    
    try:
        # Expected format: {"field": {"status": "...", "evidence": "..."}} 
        # (Verifier might refine evidence or just return status)
        verify_json = json.loads(clean_json(raw_verify_text))
    except:
        verify_json = {}

    # =========================================================================
    # 3️ Formatting Results
    # =========================================================================
    extraction_record = {"PMCID": paper_id}
    verification_records = []

    for field in FIELDS:
        # Data from Step 1 (Extraction + Evidence)
        field_data = extraction_json.get(field, {})
        # Handle case where LLM returns flat JSON (fallback) or nested JSON
        if isinstance(field_data, dict):
            value = field_data.get("value", "NA")
            evidence_from_extract = field_data.get("evidence", "NA")
        else:
            value = str(field_data)
            evidence_from_extract = "NA"

        extraction_record[field] = value
        
        # Data from Step 2 (Verification)
        verify_data = verify_json.get(field, {})
        status = verify_data.get("status", "UNKNOWN")
        
        # We record the evidence found in Step 1. 
        final_evidence = evidence_from_extract

        verification_records.append({
            "PMCID": paper_id,
            "Field": field,
            "Value": normalize_text(value),           
            "Validation": status,
            "EvidenceText": normalize_text(final_evidence), 
            "FormatCheck": validate_field(field, value)
        })

    return extraction_record, verification_records


def main():

    files = [
        os.path.join(PAPER_DIR, f)
        for f in os.listdir(PAPER_DIR)
        if f.endswith(".txt") or f.endswith(".md")
    ]
    total_files = len(files)

    if total_files == 0:
        print(f"No .txt or .md files found in {PAPER_DIR}.")
        return

    extraction_csv = "extraction_results_V0.csv"
    verification_csv = "verification_results_V0.csv"

    # Clean start (optional)
    if os.path.exists(extraction_csv): os.remove(extraction_csv)
    if os.path.exists(verification_csv): os.remove(verification_csv)

    print(f"Starting extraction for {total_files} papers...")

    completed = 0
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_paper = {executor.submit(process_paper, f): f for f in files}

        for future in as_completed(future_to_paper):
            filepath = future_to_paper[future]
            paper_id = os.path.basename(filepath).replace(".txt", "").replace(".md", "")
            completed += 1

            try:
                extract, verify = future.result()
            except Exception as exc:
                log_error(f"Paper {paper_id} Exception: {exc}")
                print(f"[{completed}/{total_files}]  FAILED - {paper_id}")
                continue

            if extract:
                # Save Extraction (One row per paper)
                ext_header = not os.path.exists(extraction_csv)
                pd.DataFrame([extract]).to_csv(
                    extraction_csv, mode='a', header=ext_header, index=False
                )

                # Save Verification (Multiple rows per paper)
                ver_header = not os.path.exists(verification_csv)
                pd.DataFrame(verify).to_csv(
                    verification_csv, mode='a', header=ver_header, index=False
                )
                
                print(f"[{completed}/{total_files}] SUCCESS - {paper_id}")
            else:
                print(f"[{completed}/{total_files}] SKIPPED - {paper_id}")

    print("\nAll papers processed successfully.")

if __name__ == "__main__":
    main()