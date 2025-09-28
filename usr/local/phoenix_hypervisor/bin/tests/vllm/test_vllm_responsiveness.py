import time
import argparse
from openai import OpenAI

def main():
    parser = argparse.ArgumentParser(description="Test the responsiveness of a local vLLM model.")
    parser.add_argument("--model-name", type=str, required=True, help="The name of the model to test.")
    parser.add_argument("--num-requests", type=int, default=10, help="The number of requests to send.")
    args = parser.parse_args()

    print(f"--- Starting vLLM Responsiveness Test ---")
    print(f"Model: {args.model_name}, Requests: {args.num_requests}")

    client = OpenAI(
        base_url="http://localhost:8000/v1",
        api_key="not-needed"
    )

    latencies = []
    prompt = "What is the capital of France?"

    for i in range(args.num_requests):
        try:
            start_time = time.time()
            response = client.chat.completions.create(
                model=args.model_name,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=50
            )
            end_time = time.time()
            latency = end_time - start_time
            latencies.append(latency)
            print(f"Request {i + 1}/{args.num_requests}: Success, Latency: {latency:.4f}s")
        except Exception as e:
            print(f"Request {i + 1}/{args.num_requests}: FAILED - {e}")

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