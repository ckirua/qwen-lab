cmake_minimum_required(VERSION 3.10)
project(hello-cpp)

add_executable(hello main.cpp)
enable_testing()
add_test(NAME hello_test COMMAND hello)
