cmake_minimum_required(VERSION 3.14)

project(animemaster VERSION 2.4.1 LANGUAGES CXX)

add_library(animemaster SHARED
  "../src/animemaster.cpp"
)

target_include_directories(animemaster PUBLIC
  "../src"
)
target_compile_features(animemaster PUBLIC cxx_std_17)

set(animemaster_bundled_libraries
  "$<TARGET_FILE:animemaster>"
  PARENT_SCOPE
)
