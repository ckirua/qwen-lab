// Minimal CUDA graphs microbench: eager launches vs graph capture/replay.
// sm_75 (Turing). Learning toy — not a llama.cpp claim.
#include <cuda_runtime.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <cmath>

#define CHECK(call)                                                            \
  do {                                                                         \
    cudaError_t err__ = (call);                                                \
    if (err__ != cudaSuccess) {                                                \
      fprintf(stderr, "CUDA error %s:%d: %s\n", __FILE__, __LINE__,            \
              cudaGetErrorString(err__));                                      \
      std::exit(1);                                                            \
    }                                                                          \
  } while (0)

__global__ void vector_add(const float *a, const float *b, float *c, int n) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n)
    c[i] = a[i] + b[i];
}

struct Timing {
  float eager_ms = 0.f;
  float graph_ms = 0.f;
  float speedup = 0.f;
};

static Timing run_once(int n, int launches, int threads) {
  size_t bytes = size_t(n) * sizeof(float);
  float *d_a = nullptr, *d_b = nullptr, *d_c = nullptr;
  CHECK(cudaMalloc(&d_a, bytes));
  CHECK(cudaMalloc(&d_b, bytes));
  CHECK(cudaMalloc(&d_c, bytes));

  std::vector<float> h(n, 1.0f);
  CHECK(cudaMemcpy(d_a, h.data(), bytes, cudaMemcpyHostToDevice));
  CHECK(cudaMemcpy(d_b, h.data(), bytes, cudaMemcpyHostToDevice));

  int blocks = (n + threads - 1) / threads;
  cudaEvent_t start, stop;
  CHECK(cudaEventCreate(&start));
  CHECK(cudaEventCreate(&stop));

  // Warmup
  for (int i = 0; i < 10; ++i)
    vector_add<<<blocks, threads>>>(d_a, d_b, d_c, n);
  CHECK(cudaDeviceSynchronize());

  // Eager
  CHECK(cudaEventRecord(start));
  for (int i = 0; i < launches; ++i)
    vector_add<<<blocks, threads>>>(d_a, d_b, d_c, n);
  CHECK(cudaEventRecord(stop));
  CHECK(cudaEventSynchronize(stop));
  float eager_ms = 0.f;
  CHECK(cudaEventElapsedTime(&eager_ms, start, stop));

  // Graph capture
  cudaStream_t stream;
  CHECK(cudaStreamCreate(&stream));
  cudaGraph_t graph;
  cudaGraphExec_t instance;
  CHECK(cudaStreamBeginCapture(stream, cudaStreamCaptureModeGlobal));
  vector_add<<<blocks, threads, 0, stream>>>(d_a, d_b, d_c, n);
  CHECK(cudaStreamEndCapture(stream, &graph));
  CHECK(cudaGraphInstantiate(&instance, graph, nullptr, nullptr, 0));

  // Warmup replay
  for (int i = 0; i < 10; ++i)
    CHECK(cudaGraphLaunch(instance, stream));
  CHECK(cudaStreamSynchronize(stream));

  CHECK(cudaEventRecord(start, stream));
  for (int i = 0; i < launches; ++i)
    CHECK(cudaGraphLaunch(instance, stream));
  CHECK(cudaEventRecord(stop, stream));
  CHECK(cudaStreamSynchronize(stream));
  float graph_ms = 0.f;
  CHECK(cudaEventElapsedTime(&graph_ms, start, stop));

  Timing t;
  t.eager_ms = eager_ms;
  t.graph_ms = graph_ms;
  t.speedup = (graph_ms > 0.f) ? (eager_ms / graph_ms) : 0.f;

  // Sanity check
  std::vector<float> out(n);
  CHECK(cudaMemcpy(out.data(), d_c, bytes, cudaMemcpyDeviceToHost));
  if (std::fabs(out[0] - 2.0f) > 1e-3f) {
    fprintf(stderr, "sanity failed: c[0]=%f\n", out[0]);
    std::exit(2);
  }

  CHECK(cudaGraphExecDestroy(instance));
  CHECK(cudaGraphDestroy(graph));
  CHECK(cudaStreamDestroy(stream));
  CHECK(cudaEventDestroy(start));
  CHECK(cudaEventDestroy(stop));
  CHECK(cudaFree(d_a));
  CHECK(cudaFree(d_b));
  CHECK(cudaFree(d_c));
  return t;
}

int main(int argc, char **argv) {
  int n = 1 << 20; // 1M
  int launches = 1000;
  int trials = 3;
  int threads = 256;
  for (int i = 1; i < argc; ++i) {
    if (std::string(argv[i]) == "--n" && i + 1 < argc)
      n = std::atoi(argv[++i]);
    else if (std::string(argv[i]) == "--launches" && i + 1 < argc)
      launches = std::atoi(argv[++i]);
    else if (std::string(argv[i]) == "--trials" && i + 1 < argc)
      trials = std::atoi(argv[++i]);
  }

  int device = 0;
  cudaDeviceProp prop{};
  CHECK(cudaGetDeviceProperties(&prop, device));
  printf("device=%s sm_%d%d n=%d launches=%d trials=%d\n", prop.name,
         prop.major, prop.minor, n, launches, trials);

  for (int t = 0; t < trials; ++t) {
    Timing r = run_once(n, launches, threads);
    // Machine-readable line for bench.sh
    printf("TRIAL\t%d\teager_ms\t%.4f\tgraph_ms\t%.4f\tspeedup\t%.4f\n", t + 1,
           r.eager_ms, r.graph_ms, r.speedup);
  }
  return 0;
}
