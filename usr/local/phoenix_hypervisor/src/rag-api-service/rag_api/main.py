from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse
import httpx
import json

# --- FastAPI Application ---
app = FastAPI()

# --- OpenAI Compatible Proxy ---
# This is the URL of the actual embedding model service that this API proxies.
EMBEDDING_MODEL_URL = "http://localhost:8001/v1/embeddings"

@app.post("/v1/embeddings")
async def create_embedding(request: Request):
    """
    This endpoint acts as a proxy, forwarding embedding requests from a client
    (like the Roo Code extension) to the actual embedding model service.
    It is designed to be compatible with the OpenAI API format.
    """
    try:
        # Get the original request body from the client
        body = await request.json()

        # Use an async HTTP client to forward the request
        async with httpx.AsyncClient() as client:
            # Forward the request to the actual embedding model service
            response = await client.post(
                EMBEDDING_MODEL_URL,
                json=body,
                # Pass through relevant headers, excluding host-specific ones
                headers={key: value for key, value in request.headers.items() if key.lower() not in ['host', 'content-length']},
                timeout=60.0,
            )

        # Raise an exception if the model service returned an error
        response.raise_for_status()

        # Return the successful response from the model service directly to the client
        return JSONResponse(content=response.json(), status_code=response.status_code)

    except httpx.RequestError as e:
        # Handle errors related to connecting to the model service
        raise HTTPException(
            status_code=502, # Bad Gateway
            detail=f"Error connecting to the embedding model service: {e}"
        )
    except httpx.HTTPStatusError as e:
        # If the model service returned an error, forward that error back to the client
        return JSONResponse(
            content=e.response.json(),
            status_code=e.response.status_code
        )
    except Exception as e:
        # Handle any other unexpected errors
        raise HTTPException(
            status_code=500, # Internal Server Error
            detail=f"An unexpected error occurred: {e}"
        )
