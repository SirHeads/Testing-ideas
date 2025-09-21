import openai
import time
import argparse

# 1. Set up argument parser
parser = argparse.ArgumentParser(description="Test the context window of a local vLLM model.")
parser.add_argument("--model-name", type=str, required=True, help="The name of the model to test.")
parser.add_argument("--max-model-len", type=int, required=True, help="The maximum model length to test.")
args = parser.parse_args()

# 2. Configure the OpenAI client to connect to the local vLLM server
client = openai.OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="not-needed" # The API key is not needed for local vLLM server
)

# 3. Define the "needle"
needle = "The secret keyword is 'phoenixfire'."
print(f"Needle: {needle}")

# 4. Construct the "haystack"
# A simple way to estimate token count is that one token is approximately 4 characters.
# We want to construct a haystack that is close to the max_model_len.
# The phrase "This is a test sentence to fill the context window. " is 55 characters long.
num_chars = args.max_model_len * 4
haystack_phrase = "This is a test sentence to fill the context window. "
repetitions = int(num_chars / len(haystack_phrase))
haystack = haystack_phrase * repetitions

# 5. Place the "needle" at the very beginning of the "haystack"
context_text = needle + "\n\n" + haystack
print(f"Constructed a haystack of approximately {len(context_text.split())} words.")


# 6. Create the prompt
prompt = f"""
Here is a long text. Please read it carefully and answer the question at the end.

---
{context_text}
---

Based on the text provided, what is the secret keyword mentioned at the beginning of this text?
"""

print(f"\nSending prompt to the model: {args.model_name}...")
start_time = time.time()

try:
    # 7. Send the prompt to the chat completions endpoint
    response = client.chat.completions.create(
        model=args.model_name,
        messages=[
            {"role": "user", "content": prompt}
        ],
        temperature=0.0,
    )

    end_time = time.time()
    duration = end_time - start_time
    
    # 7. Check if the model's response contains the "needle"
    model_response = response.choices[0].message.content
    print(f"\nModel Response:\n---\n{model_response}\n---")
    print(f"Time taken: {duration:.2f} seconds")

    if "phoenixfire" in model_response.lower():
        print("\n✅ SUCCESS: The model found the secret keyword 'phoenixfire'.")
        print("The context window test was successful.")
    else:
        print("\n❌ FAILURE: The model did not find the secret keyword 'phoenixfire'.")
        print("The context window test failed.")

except openai.APIConnectionError as e:
    print("\n❌ FAILURE: Could not connect to the vLLM server.")
    print(f"Please ensure the server is running at http://localhost:8000 and is accessible.")
    print(f"Error details: {e}")
except Exception as e:
    print(f"\n❌ An unexpected error occurred: {e}")
