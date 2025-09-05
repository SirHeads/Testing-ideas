# LXC Embedding Setup with Qdrant and vLLM for Roocode

## Overview
The goal is to enable semantic search over markdown documentation and well-commented codebases (including library docs) using high-quality embeddings. The setup involves:
- **vLLM**: Serves the `Qwen/Qwen3-Embedding-8B-GGUF:Q8_0` model in an LXC container on a Proxmox server to generate 1024-dim embeddings for text and code chunks.
- **Qdrant**: Runs in a separate LXC container on the same Proxmox server to store and retrieve embeddings for semantic search.
- **Roocode**: A Python-based application (assumed) in the vLLM LXC that processes documents, generates embeddings via vLLM, and interacts with Qdrant for storage and search.
- **Hardware**: Single 16GB VRAM GPU for vLLM, with settings optimized to leave ~4-5GB headroom for context and batching.

This document outlines key findings, setup steps, and integration details, starting with high-level considerations and diving into technical specifics.

## Key Findings

### High-Level Considerations
- **Model Selection**: `Qwen/Qwen3-Embedding-8B-GGUF:Q8_0` was chosen for its high-quality embeddings (MTEB avg ~71, retrieval ~61.5), ideal for mixed markdown/code content. Its 8-bit quantization uses ~8-9GB VRAM, fitting a 16GB GPU with headroom.
- **Qdrant in LXC**: Running Qdrant in a separate Debian-based LXC container ensures isolation, low resource use (~2-4GB RAM, 10-20GB disk), and easy Proxmox management.
- **Networking**: Both LXCs use the Proxmox `vmbr0` bridge (e.g., `192.168.1.0/24`) for low-latency internal communication (vLLM at `192.168.1.101:8000`, Qdrant at `192.168.1.100:6333/6334`).
- **Roocode Role**: Assumed to be a Python script/application that chunks documents, queries vLLM for embeddings, and manages Qdrant operations (upsert, search).
- **Performance Goals**: Optimize for quality (1024-dim embeddings, cosine similarity) while ensuring VRAM efficiency and fast retrieval for semantic search.

### Mid-Level Insights
- **vLLM Configuration**: Tuned for 16GB GPU with `--gpu-memory-utilization 0.75`, `--max-model-len 2048`, and `--max-batch-size 16` to balance quality and memory. `float16` precision and mean pooling are used for embeddings.
- **Qdrant Setup**: Uses Docker in the LXC for simplicity, with persistent storage (`/qdrant/storage`) and HNSW indexing for fast searches. Ports 6333 (HTTP) and 6334 (gRPC) are exposed.
- **Chunking Strategy**: Documents are split into 512-token chunks (with 50-token overlap) to fit within vLLM’s context limit and optimize semantic coherence for code and markdown.
- **Integration**: `roocode` uses the Qdrant Python client and `requests` to interact with vLLM and Qdrant, with batching and error handling for robustness.
- **Scalability**: The setup supports thousands of vectors initially, with disk/RAM scaling for larger datasets (e.g., millions of vectors).

### Key Challenges Addressed
- **VRAM Constraints**: Q8_0 quantization and conservative batching ensure the model fits within 16GB VRAM, leaving headroom for context.
- **Network Isolation**: Proxmox’s internal network ensures secure, fast communication between LXCs without public exposure.
- **Embedding Quality**: Prefixes (`passage:` for chunks, `query:` for searches) and normalization enhance retrieval accuracy for mixed text/code.
- **Ease of Use**: Qdrant’s Docker setup and Python-based `roocode` simplify deployment and integration.

## Detailed Setup and Integration

### 1. vLLM Configuration
The vLLM server runs in an LXC container (`192.168.1.101`) to generate embeddings using `Qwen/Qwen3-Embedding-8B-GGUF:Q8_0`.

#### Command
```bash
vllm serve Qwen/Qwen3-Embedding-8B-GGUF:Q8_0 \
  --task embedding \
  --dtype float16 \
  --gpu-memory-utilization 0.75 \
  --max-model-len 2048 \
  --max-batch-size 16 \
  --embedding-dim 1024 \
  --enable-kv-cache \
  --enable-chunked-prefill \
  --port 8000
```

#### Key Settings
- **VRAM Usage**: ~8-9GB for Q8_0 model, leaving ~4-5GB headroom on a 16GB GPU.
- **Context Length**: 2048 tokens supports most markdown/code chunks; chunk longer documents to 512-1024 tokens.
- **Batching**: 16 chunks per batch balances throughput and memory.
- **Prefixes**: Use `"passage: <chunk>"` for documents and `"query: <search>"` to boost embedding quality.
- **Normalization**: Embeddings are normalized for cosine similarity in Qdrant.

#### Monitoring
- Use `nvidia-smi` to ensure VRAM usage stays below 12GB.
- Check logs with `--log-level DEBUG` for debugging.

### 2. Qdrant Setup in Separate LXC
Qdrant runs in a Debian-based LXC container (`192.168.1.100`) using Docker for simplicity and persistence.

#### LXC Creation (Proxmox UI)
- **Template**: Debian 12.
- **Hostname**: `qdrant-lxc`.
- **Resources**: 1-2 vCPUs, 2-4GB RAM, 10-20GB disk.
- **Network**: `vmbr0`, static IP `192.168.1.100`.
- **Unprivileged**: Recommended for security.

#### Setup Script
Run the following in the Qdrant LXC:
```bash
#!/bin/bash
set -e
echo "Updating system and installing dependencies..."
apt update && apt upgrade -y
apt install -y curl docker.io
echo "Starting Docker service..."
systemctl enable docker
systemctl start docker
echo "Pulling Qdrant Docker image..."
docker pull qdrant/qdrant:latest
mkdir -p /qdrant/storage
echo "Starting Qdrant container..."
docker run -d \
  --name qdrant \
  -p 6333:6333 \
  -p 6334:6334 \
  -v /qdrant/storage:/qdrant/storage \
  qdrant/qdrant:latest
echo "Verifying Qdrant status..."
sleep 5
curl http://localhost:6333 || echo "Qdrant not reachable, check logs with: docker logs qdrant"
echo "Qdrant setup complete. Access dashboard at http://192.168.1.100:6333/dashboard"
```

#### Verification
- Check Qdrant dashboard: `http://192.168.1.100:6333/dashboard`.
- Ensure ports 6333/6334 are open:
  ```bash
  ufw allow 6333/tcp
  ufw allow 6334/tcp
  ```
  Or, on Proxmox:
  ```bash
  pve-firewall add --type in --action ACCEPT --dest 192.168.1.100 --dport 6333
  pve-firewall add --type in --action ACCEPT --dest 192.168.1.100 --dport 6334
  ```

### 3. Roocode Integration
`roocode` is assumed to be a Python script/application in the vLLM LXC (`192.168.1.101`) that processes markdown/code, generates embeddings, and interacts with Qdrant.

#### Dependencies
```bash
pip install qdrant-client requests numpy langchain
```

#### Integration Script
```python
import requests
import numpy as np
from qdrant_client import QdrantClient
from qdrant_client.http.models import Distance, VectorParams
from langchain.text_splitter import RecursiveCharacterTextSplitter
import glob
import os

# Configuration
VLLM_URL = "http://192.168.1.101:8000/v1/embeddings"
QDRANT_HOST = "192.168.1.100"
QDRANT_PORT = 6333
COLLECTION_NAME = "docs_collection"
CHUNK_SIZE = 512
BATCH_SIZE = 16

# Initialize Qdrant client
qdrant_client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT)

# Normalize embeddings
def normalize(embeddings):
    return embeddings / np.linalg.norm(embeddings, axis=-1, keepdims=True)

# Chunk documents
def chunk_documents(file_paths):
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=CHUNK_SIZE,
        chunk_overlap=50,
        length_function=len
    )
    chunks = []
    for file_path in file_paths:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            chunks.extend([f"passage: {chunk}" for chunk in text_splitter.split_text(content)])
    return chunks

# Generate embeddings
def get_embeddings(chunks, batch_size=BATCH_SIZE):
    embeddings = []
    for i in range(0, len(chunks), batch_size):
        batch = chunks[i:i + batch_size]
        payload = {
            "inputs": batch,
            "parameters": {"truncate": 2048}
        }
        try:
            response = requests.post(VLLM_URL, json=payload, timeout=30)
            response.raise_for_status()
            batch_embeddings = [data["embedding"] for data in response.json()["data"]]
            embeddings.extend(normalize(np.array(batch_embeddings)))
        except requests.RequestException as e:
            print(f"Error generating embeddings for batch {i//batch_size + 1}: {e}")
            continue
    return embeddings

# Upsert to Qdrant
def upsert_to_qdrant(chunks, embeddings):
    points = [
        {"id": idx, "vector": emb.tolist(), "payload": {"text": chunk}}
        for idx, (chunk, emb) in enumerate(zip(chunks, embeddings))
    ]
    try:
        qdrant_client.upsert(
            collection_name=COLLECTION_NAME,
            points=points
        )
        print(f"Upserted {len(points)} points to Qdrant")
    except Exception as e:
        print(f"Error upserting to Qdrant: {e}")

# Search Qdrant
def search_qdrant(query, limit=5):
    query_input = [f"query: {query}"]
    try:
        response = requests.post(VLLM_URL, json={"inputs": query_input, "parameters": {"truncate": 2048}}, timeout=30)
        response.raise_for_status()
        query_embedding = normalize(np.array(response.json()["data"][0]["embedding"]))
        results = qdrant_client.search(
            collection_name=COLLECTION_NAME,
            query_vector=query_embedding.tolist(),
            limit=limit
        )
        return [(res.payload["text"], res.score) for res in results]
    except (requests.RequestException, Exception) as e:
        print(f"Error searching Qdrant: {e}")
        return []

# Main function
def main():
    try:
        if not qdrant_client.collection_exists(COLLECTION_NAME):
            qdrant_client.create_collection(
                collection_name=COLLECTION_NAME,
                vectors_config=VectorParams(size=1024, distance=Distance.COSINE),
                hnsw_config={"m": 16, "ef_construct": 100}
            )
            print(f"Created collection {COLLECTION_NAME}")
    except Exception as e:
        print(f"Error creating collection: {e}")
        return

    doc_paths = glob.glob("/data/docs/*.md") + glob.glob("/data/code/*.py")
    chunks = chunk_documents(doc_paths)
    print(f"Generated {len(chunks)} chunks")

    embeddings = get_embeddings(chunks)
    if embeddings:
        upsert_to_qdrant(chunks, embeddings)

    query = "how to use library X function"
    results = search_qdrant(query)
    for text, score in results:
        print(f"Score: {score:.4f}, Text: {text[:100]}...")

if __name__ == "__main__":
    main()
```

#### Script Details
- **Chunking**: Splits documents into 512-token chunks with 50-token overlap using `langchain`.
- **Embedding Generation**: Queries vLLM in batches of 16, normalizes embeddings for cosine similarity.
- **Qdrant Operations**: Creates a collection (`docs_collection`) with 1024-dim vectors and HNSW indexing; upserts embeddings with text payloads; searches with query embeddings.
- **Error Handling**: Handles vLLM/Qdrant failures (e.g., timeouts, connection issues).
- **File Paths**: Update `doc_paths` to your markdown (`.md`) and code (`.py`) directories.

### 4. Testing and Validation
- **Initial Test**: Run the script with 10-20 files:
  ```bash
  python roocode.py
  ```
- **Verify Qdrant**: Check `http://192.168.1.100:6333/dashboard` for `docs_collection` and stored points.
- **Search Test**: Query “how to use library X function” and verify results (scores > 0.8 indicate good matches).
- **Debugging**:
  - vLLM errors: Check `http://192.168.1.101:8000/v1/embeddings` or logs (`journalctl -u vllm`).
  - Qdrant errors: Check `docker logs qdrant` or `curl http://192.168.1.100:6333`.
  - Poor results: Adjust `CHUNK_SIZE` (e.g., 256-1024) or verify prefixes.

### 5. Resource Requirements
- **vLLM LXC**:
  - **VRAM**: ~8-9GB for Q8_0 model, ~4-5GB headroom.
  - **RAM**: 8-16GB for Python/`roocode` and API calls.
  - **Disk**: Space for documents and vLLM model (~8-10GB).
- **Qdrant LXC**:
  - **RAM**: 2-4GB (scale to 8GB for large datasets).
  - **Disk**: 10-20GB (1000 vectors ~10MB; scale for millions).
  - **CPU**: 1-2 vCPUs.
- **Network**: `vmbr0` ensures low-latency communication. Restrict Qdrant to internal access or add TLS for security.

### 6. Scaling and Production
- **Large Datasets**: Process documents in batches (e.g., 100 files):
  ```python
  for batch in [doc_paths[i:i+100] for i in range(0, len(doc_paths), 100)]:
      chunks = chunk_documents(batch)
      embeddings = get_embeddings(chunks)
      upsert_to_qdrant(chunks, embeddings)
  ```
- **Indexing**: Increase `ef_construct` to 200 for large collections:
  ```python
  qdrant_client.set_hnsw_config(COLLECTION_NAME, {"ef_construct": 200})
  ```
- **Backups**: Snapshot Qdrant LXC or back up `/qdrant/storage`.
- **Security**: Use Qdrant API keys or TLS for production.

### 7. Potential Improvements
- **Metadata**: Add file metadata (e.g., path, type) to Qdrant payloads for filtering:
  ```python
  {"id": idx, "vector": emb.tolist(), "payload": {"text": chunk, "file": file_path}}
  ```
- **Real-Time Updates**: Modify `roocode` to watch directories for new files using `watchdog`.
- **Alternative Models**: If quality is insufficient, test `intfloat/e5-mistral-7b-instruct` or `nomic-ai/nomic-embed-text-v1.5` (~2GB VRAM).

## Conclusion
This setup enables `roocode` to generate high-quality embeddings for markdown and code, store them in Qdrant, and perform semantic searches, all within a Proxmox LXC environment. The configuration is optimized for a 16GB GPU, with robust error handling and scalability options. For further customization (e.g., non-Python `roocode`, specific frameworks, or advanced Qdrant features), provide additional details.