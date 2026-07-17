cmake_minimum_required(VERSION 3.10)
project(cpp_minimal LANGUAGES CXX)

enable_testing()
find_package(GTest REQUIRED)

add_executable(cpp_minimal_test main_test.cpp)
target_link_libraries(cpp_minimal_test GTest::gtest GTest::gtest_main)

add_test(NAME cpp_minimal_test COMMAND cpp_minimal_test)
