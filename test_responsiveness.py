import time
from openai import OpenAI

# Configure the OpenAI client to connect to the local vLLM server
client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="not-needed"  # API key is not required for local server
)

# --- Test Configuration ---
NUM_REQUESTS = 10
PROMPT = "Hello, who are you?"

def test_vllm_responsiveness():
    """
    Sends multiple requests to the vLLM server and measures response latency.
    """
    latencies = []
    print(f"Starting vLLM responsiveness test with {NUM_REQUESTS} requests...")

    for i in range(NUM_REQUESTS):
        try:
            start_time = time.time()

            # Send a simple prompt to the chat completions endpoint
            response = client.chat.completions.create(
                model="qwen2.5-7b-awq",  # Correct model name for the vLLM server
                messages=[
                    {"role": "user", "content": PROMPT}
                ],
                max_tokens=50  # Keep the response short
            )

            end_time = time.time()

            # Calculate and store the latency
            latency = end_time - start_time
            latencies.append(latency)

            print(f"Request {i + 1}/{NUM_REQUESTS}: Latency = {latency:.4f} seconds")

        except Exception as e:
            print(f"Request {i + 1} failed: {e}")

    if latencies:
        # Calculate and print statistics
        min_latency = min(latencies)
        max_latency = max(latencies)
        avg_latency = sum(latencies) / len(latencies)

        print("\n--- Test Results ---")
        print(f"Minimum Latency: {min_latency:.4f} seconds")
        print(f"Maximum Latency: {max_latency:.4f} seconds")
        print(f"Average Latency: {avg_latency:.4f} seconds")
        print("--------------------")
    else:
        print("\nNo successful requests were made.")

if __name__ == "__main__":
    test_vllm_responsiveness()