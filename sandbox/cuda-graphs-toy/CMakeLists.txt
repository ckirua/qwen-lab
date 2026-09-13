cmake_minimum_required(VERSION 3.18)
project(cuda_graphs_toy LANGUAGES CXX CUDA)

set(CMAKE_CUDA_ARCHITECTURES 75)
set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CXX_STANDARD 17)

add_executable(vector_add_graphs vector_add_graphs.cu)
target_compile_options(vector_add_graphs PRIVATE $<$<COMPILE_LANGUAGE:CUDA>:-O3>)
