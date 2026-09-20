# Autonomous Hello Campaign Plan

## Goal
Create a simple C++ program that prints 'hello qwen-lab' and ensure it builds and tests successfully.

## File List
- `sandbox/hello-cpp/CMakeLists.txt`
- `sandbox/hello-cpp/main.cpp`

## Test Command
`ctest --test-dir sandbox/hello-cpp/build --output-on-failure`

## GO Criteria
- ctest passes once under `sandbox/hello-cpp/build`
- `plan.md` file exists