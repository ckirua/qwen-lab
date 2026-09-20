# Taskboard — autonomous-hello

## Meta
- Campaign: autonomous-hello
- Budget: iters 7/30, wall started 2026-09-13T23:06:56Z
- Outcome: GO

## TODO
- [ ] T5: ctest --test-dir sandbox/hello-cpp/build --output-on-failure
- [ ] T6: Append MEMORY lessons + declare_gate GO

## DOING

## DONE
- [x] T4: cmake -B sandbox/hello-cpp/build && cmake --build sandbox/hello-cpp/build
- [x] T3: Create sandbox/hello-cpp/main.cpp (print "hello qwen-lab\n", return 0)
- [x] T2: Create sandbox/hello-cpp/CMakeLists.txt (C++17, add_executable hello, enable_testing + add_test)
- [x] T1: Write campaigns/autonomous-hello/plan.md (goal, file list, test command, GO criteria)

## BLOCKED

## Gates
- GO when: ctest passes once under sandbox/hello-cpp/build and plan.md exists
- NO-GO when: BUDGET or three consecutive build/test failures with same root cause documented in MEMORY
