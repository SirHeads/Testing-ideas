#!/usr/bin/env python3
#
# File: embedding_server.py
# Description: A dedicated FastAPI application to serve sentence embedding models.
#              It loads a SentenceTransformer model on startup and provides an
#              OpenAI-compatible API endpoint for generating embeddings.
# Author: Roo, AI Software Engineer

import os
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from sentence_transformers import SentenceTransformer
import torch
from typing import List, Union

# --- Pydantic Models for API Data Validation ---

class EmbeddingRequest(BaseModel):
    """Defines the structure for an embedding request."""
    model: str
    input: Union[str, List[str]]

class EmbeddingData(BaseModel):
    """Represents a single embedding vector in the response."""
    object: str = "embedding"
    embedding: List[float]
    index: int

class UsageData(BaseModel):
    """Represents token usage information."""
    prompt_tokens: int = 0
    total_tokens: int = 0

class EmbeddingResponse(BaseModel):
    """Defines the structure for the embedding API response."""
    object: str = "list"
    data: List[EmbeddingData]
    model: str
    usage: UsageData

# --- FastAPI Application Setup ---

app = FastAPI()
model = None
model_name = ""

@app.on_event("startup")
def startup_event():
    """
    Handles the model loading process when the server starts.
    It retrieves the model name from an environment variable and loads
    the SentenceTransformer model, optimizing it for the available hardware.
    """
    global model, model_name
    
    # Retrieve the model name from the environment variable
    model_name = os.getenv("EMBEDDING_MODEL_NAME")
    if not model_name:
        raise RuntimeError("EMBEDDING_MODEL_NAME environment variable not set.")

    print(f"Loading model: {model_name}...")

    # Determine the device to use (CUDA if available, otherwise CPU)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Using device: {device}")

    # Load the SentenceTransformer model
    model = SentenceTransformer(model_name, device=device)
    
    # Optimize the model for inference if on CUDA
    if device == "cuda":
        model.half() # Use half-precision for faster inference
        
    model.eval() # Set the model to evaluation mode
    print("Model loaded successfully.")

# --- API Endpoints ---

@app.get("/health")
def health_check():
    """A simple health check endpoint to verify the server is running."""
    return {"status": "ok"}

@app.post("/v1/embeddings", response_model=EmbeddingResponse)
def create_embeddings(request: EmbeddingRequest):
    """
    Generates embeddings for the given input text(s).
    This endpoint is designed to be compatible with the OpenAI embeddings API.
    """
    global model, model_name

    if model is None:
        raise HTTPException(status_code=503, detail="Model is not loaded yet.")

    # Ensure the requested model matches the loaded model
    if request.model != model_name:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid model requested. This server is serving '{model_name}', but you requested '{request.model}'."
        )

    # Handle both single string and list of strings for input
    inputs = [request.input] if isinstance(request.input, str) else request.input
    
    # Generate embeddings
    try:
        embeddings = model.encode(inputs, convert_to_tensor=True)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error during embedding generation: {e}")

    # Format the response data
    response_data = [
        EmbeddingData(embedding=emb.tolist(), index=i)
        for i, emb in enumerate(embeddings)
    ]

    return EmbeddingResponse(
        data=response_data,
        model=model_name,
        usage=UsageData() # Token usage is not tracked in this simple server
    )

if __name__ == "__main__":
    import uvicorn
    # This block allows running the server directly for testing
    # In production, it will be run by a process manager like systemd/gunicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)