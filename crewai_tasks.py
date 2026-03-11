from crewai import Task
from schema import FIELDS

def build_combined_extraction_task(agent, paper_text):

    return Task(
        description=f"""
Extract the following fields as strict JSON.

Rules:
- The exact quotes/sentences from the paper as evidence.
- If not explicitly stated, return "NA".
- Do NOT infer.
- Output JSON only.
- All fields must appear.

Fields:
{FIELDS}

Paper content:
{paper_text}

Output format: Strictly A JSON dictionary where each key is a field name, and the value is another dictionary:
{{"field_name": {{"value": "...", "evidence": "..."}}}}

""",
        agent=agent,
        expected_output="A Strictly JSON object containing values and exact text quotes for every field."
    )



def build_verification_task(agent, extraction_results):
    return Task(
        description=f"""
Review the following extracted data and evidence:
{extraction_results}

Verify if the 'value' is correctly supported by the 'evidence'. 
Provide a final verification status for each field: VALID, INVALID, or NOT_FOUND.

Output format: Strictly A JSON dictionary: {{"field_name": {{"status": "...", "evidence": "..."}}}}
""",
        agent=agent,
        expected_output="A Strictly JSON object with final validation statuses."
    )