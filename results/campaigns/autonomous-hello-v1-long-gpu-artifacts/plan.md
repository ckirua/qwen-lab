# Autonomous Hello Campaign Plan

## Goal
- Develop a simple C++ program that prints 'hello qwen-lab' and verifies its correctness using CMake and ctest.

## File List
- `sandbox/hello-cpp/CMakeLists.txt`
- `sandbox/hello-cpp/main.cpp`

## Test Command
- `ctest --test-dir sandbox/hello-cpp/build --output-on-failure`

## GO Criteria
- Successful ctest run with no errors.
- Existence of `campaigns/autonomous-hello/plan.md` file.