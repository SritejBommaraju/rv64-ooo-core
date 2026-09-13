CXX = g++
CXXFLAGS = -O2 -std=c++17 -Wall -Wextra

.PHONY: all test clean

all: iss

iss: main.cpp iss.cpp iss.h
	$(CXX) $(CXXFLAGS) -o iss main.cpp iss.cpp

test: test_iss
	./test_iss

test_iss: test_iss.cpp iss.cpp iss.h
	$(CXX) $(CXXFLAGS) -o test_iss test_iss.cpp iss.cpp

clean:
	rm -f iss test_iss
