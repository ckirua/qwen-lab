## autonomous-hello Campaign Plan

### Goal
- Develop a simple C++ program that prints 'hello qwen-lab' and test it using CMake and ctest.

### File List
- `campaigns/autonomous-hello/plan.md`
- `sandbox/hello-cpp/CMakeLists.txt`
- `sandbox/hello-cpp/main.cpp`

### Test Command
- `ctest --test-dir sandbox/hello-cpp/build --output-on-failure`

### GO Criteria
- Successful ctest output indicating the test passed.