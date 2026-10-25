#include "move_journal.hpp"
#include <iostream>
#include <stdexcept>
#include <string>

// Private local IPC only; no network access and no arbitrary JSON/log output.
int main(int argc, char **argv) {
  try {
    if (argc < 3 || argc > 4) throw std::runtime_error("invalid_request");
    tnt::move::Journal journal(argv[2]);
    const std::string action(argv[1]);
    if (action == "initialize" && argc == 3) {
      journal.Initialize();
      std::cout << "ready\n";
      return 0;
    }
    if (action == "read" && argc == 3) {
      const auto result = journal.Read();
      std::cout << (result.empty() ? "empty\n" : result);
      return 0;
    }
    std::string text;
    char ch;
    while (std::cin.get(ch)) {
      if (text.size() >= 8192) throw std::runtime_error("invalid_request");
      text += ch;
    }
    const auto record = tnt::move::DecodeRecord(text);
    if (action == "begin" && argc == 3) {
      std::cout << tnt::move::EncodeRecord(journal.Begin(record));
      return 0;
    }
    if (action == "update" && argc == 4) {
      const std::string revision(argv[3]);
      if (revision.empty() || revision.size() > 16 || revision.find_first_not_of("0123456789") != std::string::npos)
        throw std::runtime_error("invalid_request");
      std::cout << tnt::move::EncodeRecord(journal.Update(record, std::stoull(revision)));
      return 0;
    }
    throw std::runtime_error("invalid_request");
  } catch (const std::exception &error) {
    const std::string code(error.what());
    if (code == "journal_busy" || code == "unresolved_operation" || code == "operation_already_exists")
      std::cout << code << '\n';
    else std::cout << "journal_unavailable\n";
    return 1;
  } catch (...) {
    std::cout << "journal_unavailable\n";
    return 1;
  }
}
