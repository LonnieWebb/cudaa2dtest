cmake_minimum_required(VERSION 3.20 FATAL_ERROR)

project(CUDA_A2D_TEST LANGUAGES CXX CUDA)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(meshimport meshimport.cpp)
add_executable(cudatest cudatest.cu)