import os
import glob
import pubmed_parser as pp
from bs4 import BeautifulSoup

INPUT_DIR = "paper267_xml"
OUTPUT_DIR = "paper267_txt"

if not os.path.exists(OUTPUT_DIR):
    os.makedirs(OUTPUT_DIR)

def process_single_xml(xml_path, output_path):
    try:
        # 1. 使用 BeautifulSoup 提取标题和年份
        with open(xml_path, "r", encoding="utf-8") as f:
            soup = BeautifulSoup(f, "xml")

        title_tag = soup.find("article-title") or soup.find("title")
        title = title_tag.get_text().strip() if title_tag else "Unknown Title"

        year_tag = soup.find("pub-date")
        if year_tag and year_tag.find("year"):
            year = year_tag.find("year").get_text(strip=True)
        else:
            year = "Unknown Year"

        # 2. 使用 pubmed_parser 提取，
        try:
            data = pp.parse_pubmed_xml(xml_path)
        except Exception:
            data = {} 

        # 提取期刊 
        journal = data.get("journal")
        if not journal or journal == "Unknown Journal":
            journal_tag = soup.find("journal-title")
            journal = journal_tag.get_text().strip() if journal_tag else "Unknown Journal"
        
        # 提取 PMCID
        pmcid = data.get("pmcid")
        if not pmcid:
            pmcid_tag = soup.find("article-id", {"pub-id-type": "pmcid"})
            pmcid = pmcid_tag.get_text().strip() if pmcid_tag else "Unknown PMCID"

        # 清理不需要的
        for unwanted_tag in soup.find_all(["ref-list", "xref", "fig", "table-wrap", "disp-formula"]):
            unwanted_tag.decompose()

        # 提取摘要
        abstract_tag = soup.find("abstract")
        abstract_text = ""
        if abstract_tag:
            abs_paragraphs = [p.get_text(separator=' ', strip=True) for p in abstract_tag.find_all(['title', 'p'])]
            abstract_text = "\n".join(abs_paragraphs)

        # 提取正文主体内容
        body_tag = soup.find("body")
        body_text = ""
        if body_tag:
            body_paragraphs = []
            for element in body_tag.find_all(["title", "p", "sec"]):
                if element.name in ['title', 'p']:
                    text = element.get_text(separator=' ', strip=True)
                    if text:
                        body_paragraphs.append(text)
            body_text = "\n".join(body_paragraphs)

        full_text = ""
        if abstract_text:
            full_text += "ABSTRACT:\n" + abstract_text + "\n\n"
        if body_text:
            full_text += "BODY:\n" + body_text

        # 处理作者列表
        author_list = data.get("author_list", [])
        if isinstance(author_list, list) and len(author_list) > 0 and isinstance(author_list[0], list):
            authors = "; ".join([f"{a[1]} {a[0]}" for a in author_list])
        else:
            
            authors_array = []
            for contrib in soup.find_all("contrib", {"contrib-type": "author"}):
                surname = contrib.find("surname")
                given_name = contrib.find("given-names")
                s = surname.get_text().strip() if surname else ""
                g = given_name.get_text().strip() if given_name else ""
                if s or g:
                    authors_array.append(f"{g} {s}".strip())
            authors = "; ".join(authors_array) if authors_array else "Unknown Authors"

        # 3. 输出保存
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(f"Title: {title}\n")
            f.write(f"Authors: {authors}\n")
            f.write(f"Journal: {journal}\n")
            f.write(f"Year: {year}\n")
            f.write(f"PMCID: {pmcid}\n")
            f.write("-" * 20 + " CONTENT " + "-" * 20 + "\n")
            f.write(full_text)
            
        return True
    except Exception as e:
        print(f"[错误] {xml_path}: {e}")
        return False

def main():
    xml_files = glob.glob(os.path.join(INPUT_DIR, "*.xml"))
    total_files = len(xml_files)
    
    if total_files == 0:
        print(f"未在 {INPUT_DIR} 中找到 XML 。")
        return

    print(f"找到 {total_files} 个 XML ，开始转换...")
    
    success_count = 0
    for idx, xml_file in enumerate(xml_files, 1):
        filename = os.path.basename(xml_file)
        txt_filename = filename.replace(".xml", ".txt")
        output_path = os.path.join(OUTPUT_DIR, txt_filename)
        
        print(f"[{idx}/{total_files}] 正在转换: {filename} ...", end=" ")
        
        if process_single_xml(xml_file, output_path):
            print("成功")
            success_count += 1
        else:
            print("失败")

    print(f"\n全部完成。成功转换 {success_count}/{total_files} 个文件，保存在 {OUTPUT_DIR} 文件夹中。")

if __name__ == "__main__":
    main()