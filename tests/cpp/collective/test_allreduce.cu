/**
 * Copyright 2023-2024, XGBoost Contributors
 */
#if defined(XGBOOST_USE_NCCL)
#include <gtest/gtest.h>
#include <thrust/host_vector.h>  // for host_vector

#include "../../../src/common/cuda_rt_utils.h"     // for AllVisibleGPUs
#include "../../../src/common/device_helpers.cuh"  // for ToSpan,  device_vector
#include "../../../src/common/type.h"              // for EraseType
#include "test_worker.cuh"                         // for NCCLWorkerForTest
#include "test_worker.h"                           // for WorkerForTest, TestDistributed

namespace xgboost::collective {
namespace {
class MGPUAllreduceTest : public SocketTest {};

class Worker : public NCCLWorkerForTest {
 public:
  using NCCLWorkerForTest::NCCLWorkerForTest;

  void BitOr() {
    dh::device_vector<std::uint32_t> data(comm_.World(), 0);
    data[comm_.Rank()] = ~std::uint32_t{0};
    auto rc = nccl_coll_->Allreduce(*nccl_comm_, common::EraseType(dh::ToSpan(data)),
                                    ArrayInterfaceHandler::kU4, Op::kBitwiseOR);
    SafeColl(rc);
    thrust::host_vector<std::uint32_t> h_data(data.size());
    thrust::copy(data.cbegin(), data.cend(), h_data.begin());
    for (auto v : h_data) {
      ASSERT_EQ(v, ~std::uint32_t{0});
    }
  }

  void Acc() {
    dh::device_vector<double> data(314, 1.5);
    auto rc = nccl_coll_->Allreduce(*nccl_comm_, common::EraseType(dh::ToSpan(data)),
                                    ArrayInterfaceHandler::kF8, Op::kSum);
    SafeColl(rc);
    for (std::size_t i = 0; i < data.size(); ++i) {
      auto v = data[i];
      ASSERT_EQ(v, 1.5 * static_cast<double>(comm_.World())) << i;
    }
  }
};
}  // namespace

TEST_F(MGPUAllreduceTest, BitOr) {
  auto n_workers = curt::AllVisibleGPUs();
  TestDistributed(n_workers, [=](std::string host, std::int32_t port, std::chrono::seconds timeout,
                                 std::int32_t r) {
    Worker w{host, port, timeout, n_workers, r};
    w.Setup();
    w.BitOr();
  });
}

TEST_F(MGPUAllreduceTest, Sum) {
  auto n_workers = curt::AllVisibleGPUs();
  TestDistributed(n_workers, [=](std::string host, std::int32_t port, std::chrono::seconds timeout,
                                 std::int32_t r) {
    Worker w{host, port, timeout, n_workers, r};
    w.Setup();
    w.Acc();
  });
}
}  // namespace xgboost::collective
#endif  // defined(XGBOOST_USE_NCCL)
