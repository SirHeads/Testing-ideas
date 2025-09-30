#
# File: test_vllm_responsiveness.py
#
# Description:
#   This script serves as a simple load and performance test for a vLLM model.
#   It sends a specified number of identical, simple prompts to the vLLM server
#   and measures the latency of each request. After completing all requests, it
#   calculates and prints the minimum, maximum, and average latency, providing a
#   basic benchmark of the model's responsiveness and performance.
#
# Dependencies:
#   - `openai` Python package.
#   - A running vLLM server accessible at http://localhost:8000.
#
# Inputs (Command-Line Arguments):
#   --model-name: The name of the model being served by vLLM.
#   --num-requests: The number of sequential requests to send to the model.
#
# Outputs:
#   - Prints the status and latency of each individual request.
#   - Provides a final summary of the minimum, maximum, and average latency for
#     all successful requests.
#

import time
import argparse
from openai import OpenAI

def main():
    """Main function to run the responsiveness test."""
    
    # --- 1. Argument Parsing ---
    # Set up the command-line interface to accept the model name and number of requests.
    parser = argparse.ArgumentParser(description="Test the responsiveness of a local vLLM model.")
    parser.add_argument("--model-name", type=str, required=True, help="The name of the model to test.")
    parser.add_argument("--num-requests", type=int, default=10, help="The number of requests to send.")
    args = parser.parse_args()

    print(f"--- Starting vLLM Responsiveness Test ---")
    print(f"Model: {args.model_name}, Requests: {args.num_requests}")

    # --- 2. OpenAI Client Configuration ---
    # Configure the client to connect to the local vLLM server.
    client = OpenAI(
        base_url="http://localhost:8000/v1",
        api_key="not-needed"  # API key is not required for local instances.
    )

    # --- 3. Test Execution ---
    latencies = []
    prompt = "What is the capital of France?"  # A simple, consistent prompt for all requests.

    # Loop for the specified number of requests.
    for i in range(args.num_requests):
        try:
            start_time = time.time()
            # Send the request to the vLLM server.
            client.chat.completions.create(
                model=args.model_name,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=50  # Limit the response length to keep the test focused on latency.
            )
            end_time = time.time()
            
            # Calculate and store the latency for this request.
            latency = end_time - start_time
            latencies.append(latency)
            print(f"Request {i + 1}/{args.num_requests}: Success, Latency: {latency:.4f}s")
        
        except Exception as e:
            # Report any requests that fail.
            print(f"Request {i + 1}/{args.num_requests}: FAILED - {e}")

    # --- 4. Results Summary ---
    # If any requests were successful, calculate and display the latency statistics.
    if latencies:
        min_latency = min(latencies)
        max_latency = max(latencies)
        avg_latency = sum(latencies) / len(latencies)
        print("\n--- Test Results ---")
        print(f"Minimum Latency: {min_latency:.4f}s")
        print(f"Maximum Latency: {max_latency:.4f}s")
        print(f"Average Latency: {avg_latency:.4f}s")
        print("--------------------")
    else:
        print("\n--- No successful requests were made. ---")

if __name__ == "__main__":
    main()