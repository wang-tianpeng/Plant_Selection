from crewai import Agent
import os
from crewai.llm import LLM

llm = LLM(
    model="deepseek/deepseek-chat", 
    api_key=os.getenv("DEEPSEEK_API_KEY"),  
    api_base="https://api.deepseek.com",
    temperature=0.2,  # 降低随机性
)
extractor_agent = Agent(
    role="Genomics Research Analyst",
    goal="Extract structured data and its corresponding source text evidence from papers simultaneously.",
    backstory="You are a expert in population genomics researcher. Your job is to read papers and not only extract key parameters but also quote the exact sentence as evidence for each parameter to ensure accuracy.",
    llm=llm,
    max_iter=1,
    verbose=False
)

verifier_agent = Agent(
    role="Scientific Validator",
    goal="Validate extracted value and provided evidence text",
    backstory="Strict reviewer ensuring no hallucination.",
    llm=llm,
    max_iter=1,
    verbose=False
)
