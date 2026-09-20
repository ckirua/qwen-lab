cmake_minimum_required(VERSION 3.10)
project(hello-cpp)

set(CMAKE_CXX_STANDARD 17)

add_executable(hello main.cpp)
enable_testing()

add_test(NAME hello_test COMMAND hello)
