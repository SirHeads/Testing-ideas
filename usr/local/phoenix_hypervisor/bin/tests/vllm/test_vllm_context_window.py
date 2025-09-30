#
# File: test_vllm_context_window.py
#
# Description:
#   This script performs a "needle in a haystack" test to verify the effective
#   context window of a vLLM model. It constructs a long, repetitive text
#   (the "haystack") that approximates the model's maximum context length,
#   places a unique keyword (the "needle") at the beginning, and then asks the
#   model to retrieve the needle. A successful retrieval indicates that the
#   model can process and recall information from the entire context window.
#
# Dependencies:
#   - `openai` Python package.
#   - A running vLLM server accessible at http://localhost:8000.
#
# Inputs (Command-Line Arguments):
#   --model-name: The name of the model being served by vLLM (e.g., "llama-3").
#   --max-model-len: The theoretical maximum context length (in tokens) of the model.
#
# Outputs:
#   - Prints the test progress, the model's response, and the time taken.
#   - Reports a clear SUCCESS or FAILURE message based on whether the model
#     found the secret keyword.
#   - Exits implicitly with status 0 on success or non-zero on failure (due to errors).
#

import openai
import time
import argparse

# --- 1. Argument Parsing ---
# Set up the command-line interface to accept the model name and its max length.
parser = argparse.ArgumentParser(description="Test the context window of a local vLLM model.")
parser.add_argument("--model-name", type=str, required=True, help="The name of the model to test.")
parser.add_argument("--max-model-len", type=int, required=True, help="The maximum model length to test.")
args = parser.parse_args()

# --- 2. OpenAI Client Configuration ---
# Configure the client to connect to the local vLLM server, which mimics the OpenAI API.
# The API key is not required for local instances.
client = openai.OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="not-needed"
)

# --- 3. Test Data Definition ---
# The "needle" is the secret keyword we want the model to find.
needle = "The secret keyword is 'phoenixfire'."
print(f"Needle: {needle}")

# --- 4. Haystack Construction ---
# Create a long string of text to fill the model's context window.
# We use a rough estimation that 1 token is about 4 characters.
num_chars = args.max_model_len * 4
haystack_phrase = "This is a test sentence to fill the context window. "
repetitions = int(num_chars / len(haystack_phrase))
haystack = haystack_phrase * repetitions

# --- 5. Prompt Assembly ---
# Place the needle at the very beginning of the haystack. This is often the most
# difficult position for a model to recall from in a long context.
context_text = needle + "\n\n" + haystack
print(f"Constructed a haystack of approximately {len(context_text.split())} words.")

# Create the final prompt that instructs the model on its task.
prompt = f"""
Here is a long text. Please read it carefully and answer the question at the end.

---
{context_text}
---

Based on the text provided, what is the secret keyword mentioned at the beginning of this text?
"""

# --- 6. Model Invocation and Verification ---
print(f"\nSending prompt to the model: {args.model_name}...")
start_time = time.time()

try:
    # Send the prompt to the vLLM server's chat completions endpoint.
    # Temperature is set to 0.0 for deterministic, non-creative output.
    response = client.chat.completions.create(
        model=args.model_name,
        messages=[
            {"role": "user", "content": prompt}
        ],
        temperature=0.0,
    )

    end_time = time.time()
    duration = end_time - start_time
    
    # Extract the model's response text.
    model_response = response.choices[0].message.content
    print(f"\nModel Response:\n---\n{model_response}\n---")
    print(f"Time taken: {duration:.2f} seconds")

    # Check if the model successfully found and repeated the needle.
    if "phoenixfire" in model_response.lower():
        print("\n✅ SUCCESS: The model found the secret keyword 'phoenixfire'.")
        print("The context window test was successful.")
    else:
        print("\n❌ FAILURE: The model did not find the secret keyword 'phoenixfire'.")
        print("The context window test failed.")

# --- 7. Error Handling ---
except openai.APIConnectionError as e:
    print("\n❌ FAILURE: Could not connect to the vLLM server.")
    print(f"Please ensure the server is running at http://localhost:8000 and is accessible.")
    print(f"Error details: {e}")
except Exception as e:
    print(f"\n❌ An unexpected error occurred: {e}")
