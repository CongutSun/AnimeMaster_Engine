cmake_minimum_required(VERSION 3.10)
project(animemaster_library VERSION 0.0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(animemaster SHARED animemaster.cpp)

set_target_properties(animemaster PROPERTIES
  PUBLIC_HEADER animemaster.h
  OUTPUT_NAME "animemaster"
)
target_compile_definitions(animemaster PUBLIC DART_SHARED_LIB)