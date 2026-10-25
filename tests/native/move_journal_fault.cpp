#include "move_journal.hpp"
#include <cstdlib>
#include <iostream>
#include <iterator>
#include <string>

// Test-only executable. No fault injection is compiled into the packaged CLI.
int main(int argc, char **argv) {
  if (argc != 4) return 2;
  try {
    const std::string stop(argv[3]);
    tnt::move::Journal journal(argv[2], [&](const char *point) {
      if (stop == point) std::_Exit(73);
    });
    const std::string input((std::istreambuf_iterator<char>(std::cin)), {});
    auto record = tnt::move::DecodeRecord(input);
    if (std::string(argv[1]) == "begin") journal.Begin(record);
    else journal.Update(record, record.revision - 1);
    return 0;
  } catch (...) { return 1; }
}
