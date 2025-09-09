import os
import logging
import fnmatch
import requests
from dotenv import load_dotenv

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def parse_rooignore(rooignore_path):
    """Parses the .rooignore file and returns a list of patterns."""
    if not os.path.exists(rooignore_path):
        return []
    with open(rooignore_path, 'r') as f:
        return [line.strip().rstrip('/') for line in f if line.strip() and not line.startswith('#')]

def is_ignored(path, ignore_patterns):
    """Checks if a file or directory should be ignored."""
    for pattern in ignore_patterns:
        if fnmatch.fnmatch(path, pattern) or any(fnmatch.fnmatch(part, pattern) for part in path.split(os.sep)):
            return True
    return False

def main():
    """Main function to run the indexing process."""
    load_dotenv()

    rag_api_url = os.getenv("RAG_API_URL")
    if not rag_api_url:
        logging.error("RAG_API_URL environment variable not set. Please check your .env file.")
        return

    workspace_path = os.path.abspath('.')

    if not os.path.isdir(workspace_path):
        logging.error(f"The workspace path does not exist or is not a directory: {workspace_path}")
        return

    rooignore_path = os.path.join(workspace_path, ".rooignore")
    ignore_patterns = parse_rooignore(rooignore_path)
    
    logging.info(f"Starting to scan workspace: {workspace_path}")

    for root, dirs, files in os.walk(workspace_path):
        # Filter directories
        dirs[:] = [d for d in dirs if not is_ignored(os.path.join(root, d), ignore_patterns)]
        
        for file in files:
            file_path = os.path.join(root, file)
            
            if is_ignored(file_path, ignore_patterns):
                continue

            try:
                logging.info(f"Processing file: {file_path}")
                
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                
                response = requests.post(f"{rag_api_url}/index", json={"content": content})
                
                if response.status_code == 200:
                    logging.info(f"Successfully indexed {file_path}")
                else:
                    logging.error(f"Failed to index {file_path}. Status code: {response.status_code}, Response: {response.text}")

            except Exception as e:
                logging.error(f"Failed to process file {file_path}: {e}")

    logging.info("Indexing complete.")

if __name__ == "__main__":
    main()