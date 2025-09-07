import os
import re
import yaml

# Define the new unified frontmatter standard
UNIFIED_FRONTMATTER_TEMPLATE = {
    "title": "Document Title",
    "summary": "A brief, one-to-two-sentence summary of the document's purpose and content.",
    "document_type": "Strategy | Technical | Business Case | Report",
    "status": "Draft | In Review | Approved | Archived",
    "version": "1.0.0",
    "author": "Author Name",
    "owner": "Team/Individual Name",
    "tags": [],
    "review_cadence": "Annual | Quarterly | Monthly | None",
    "last_reviewed": "YYYY-MM-DD"
}

def parse_frontmatter(content):
    """
    Parses YAML frontmatter from a markdown file.
    Returns a tuple: (frontmatter_dict, content_without_frontmatter, frontmatter_raw_lines)
    """
    frontmatter = {}
    content_without_frontmatter = content
    frontmatter_raw_lines = []

    match = re.match(r'---\s*\n(.*?)\n---\s*\n(.*)', content, re.DOTALL)
    if match:
        frontmatter_str = match.group(1)
        content_without_frontmatter = match.group(2)
        frontmatter_raw_lines = frontmatter_str.splitlines()
        try:
            frontmatter = yaml.safe_load(frontmatter_str)
            if frontmatter is None: # Handle empty frontmatter
                frontmatter = {}
        except yaml.YAMLError as e:
            print(f"Error parsing YAML frontmatter: {e}")
            frontmatter = {}
    return frontmatter, content_without_frontmatter, frontmatter_raw_lines

def convert_to_unified_frontmatter(old_frontmatter):
    """
    Converts existing frontmatter to the new unified standard.
    Fills in missing fields with placeholders from the template.
    """
    new_frontmatter = UNIFIED_FRONTMATTER_TEMPLATE.copy()

    # Map existing fields to new standard
    if old_frontmatter:
        for key, value in old_frontmatter.items():
            if key in new_frontmatter:
                if key == "tags" and isinstance(value, str):
                    new_frontmatter[key] = [tag.strip() for tag in value.split(',')]
                else:
                    new_frontmatter[key] = value
            elif key == "document_type" and value:
                new_frontmatter["document_type"] = value
            elif key == "status" and value:
                new_frontmatter["status"] = value
            elif key == "owner" and value:
                new_frontmatter["owner"] = value
            elif key == "review_cadence" and value:
                new_frontmatter["review_cadence"] = value
            elif key == "last_reviewed" and value:
                new_frontmatter["last_reviewed"] = value
            # Handle fields that might be in old standard A but not in template directly
            elif key == "title" and value:
                new_frontmatter["title"] = value
            elif key == "summary" and value:
                new_frontmatter["summary"] = value
            elif key == "author" and value:
                new_frontmatter["author"] = value
            elif key == "version" and value:
                new_frontmatter["version"] = value

    # Ensure tags is a list
    if not isinstance(new_frontmatter.get("tags"), list):
        new_frontmatter["tags"] = []

    return new_frontmatter

def update_markdown_file(filepath):
    """
    Reads a markdown file, updates its frontmatter to the unified standard,
    and writes the content back.
    """
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    old_frontmatter, content_without_frontmatter, _ = parse_frontmatter(content)
    new_frontmatter_dict = convert_to_unified_frontmatter(old_frontmatter)

    # Format new frontmatter as YAML string
    new_frontmatter_str = yaml.dump(new_frontmatter_dict, sort_keys=False, default_flow_style=False, allow_unicode=True)

    # Reconstruct the file content
    updated_content = f"---\n{new_frontmatter_str}---\n{content_without_frontmatter.strip()}\n"

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(updated_content)
    print(f"Updated frontmatter for: {filepath}")

def main():
    directories_to_scan = ["phoenix_hypervisor", "Thinkheads.AI"]
    markdown_files = []

    for directory in directories_to_scan:
        for root, _, files in os.walk(directory):
            for file in files:
                if file.endswith(".md"):
                    markdown_files.append(os.path.join(root, file))

    for filepath in markdown_files:
        update_markdown_file(filepath)

if __name__ == "__main__":
    main()