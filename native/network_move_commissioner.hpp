#pragma once
#include "network_move.hpp"
#include <memory>
namespace tnt::move {
// Real pinned-library adapter. The application probe remains independent and GET-only.
std::unique_ptr<Transport> CreateCommissionerTransport(bool discard_set_result_for_lab = false, bool trace_for_lab = false);
}
