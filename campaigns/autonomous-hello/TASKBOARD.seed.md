# Taskboard — autonomous-hello

## Meta
- Campaign: autonomous-hello
- Budget: iters 0/30, wall started (unset)
- Outcome:

## TODO
- [ ] T1: Write campaigns/autonomous-hello/plan.md (goal, file list, test command, GO criteria)
- [ ] T2: Create sandbox/hello-cpp/CMakeLists.txt (C++17, add_executable hello, enable_testing + add_test)
- [ ] T3: Create sandbox/hello-cpp/main.cpp (print "hello qwen-lab\n", return 0)
- [ ] T4: cmake -B sandbox/hello-cpp/build && cmake --build sandbox/hello-cpp/build
- [ ] T5: ctest --test-dir sandbox/hello-cpp/build --output-on-failure
- [ ] T6: Append MEMORY lessons + declare_gate GO

## DOING

## DONE

## BLOCKED

## Gates
- GO when: ctest passes once under sandbox/hello-cpp/build and plan.md exists
- NO-GO when: BUDGET or three consecutive build/test failures with same root cause documented in MEMORY
