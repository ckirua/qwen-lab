## autonomous-hello Campaign Plan

### Goal
- Write a simple C++ program that prints 'hello qwen-lab' and build/test it using CMake and ctest.

### File List
- `sandbox/hello-cpp/CMakeLists.txt`
- `sandbox/hello-cpp/main.cpp`

### Test Command
- `ctest --test-dir sandbox/hello-cpp/build --output-on-failure`

### GO Criteria
- Successful ctest output indicating a passing test.

### Notes
- Ensure the build directory is created and built before running tests.
- Use CMake version 3.10 or later for compatibility.
- The program should compile and run without errors.