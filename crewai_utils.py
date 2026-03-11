import logging
import json
import re
from tenacity import retry, stop_after_attempt, wait_fixed
from config import RETRY_TIMES

logging.basicConfig(
    filename="meta_extraction.log",
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)

def clean_json(text):
    """
    Robust JSON cleaner.
    """
    if not text:
        return ""
    
    # 1. Try to find content within ```json ... ``` code blocks
    match = re.search(r'```json\s*(.*?)\s*```', text, re.DOTALL)
    if match:
        text = match.group(1)
    
    # 2. Try to find content within generic ``` ... ``` code blocks
    elif re.search(r'```\s*(.*?)\s*```', text, re.DOTALL):
        match = re.search(r'```\s*(.*?)\s*```', text, re.DOTALL)
        text = match.group(1)

    # 3. Find the first '{' and the last '}' to strip conversational padding
    start = text.find('{')
    end = text.rfind('}')
    
    if start != -1 and end != -1:
        return text[start:end+1]
    
    return text.strip()

@retry(stop=stop_after_attempt(RETRY_TIMES), wait=wait_fixed(2))
def run_crew(crew):
    return crew.kickoff()

def log_info(msg):
    logging.info(msg)

def log_error(msg):
    logging.error(msg)