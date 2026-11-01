#!/usr/bin/env bash
set -e
export PATH="$HOME/.local/bin:$PATH"
cd /home/hp2/workspace/rclone-storage-automation

set -a
source .env
set +a

echo "=== 1. Benchmarking Sequential Transfer (--transfers 1) ==="
START=$(date +%s%N)
rclone copy samples/source/documents :s3:testpress-source/bench-seq \
  --config /dev/null --transfers 1 --checkers 1
END=$(date +%s%N)
SEQ_MS=$(( (END - START) / 1000000 ))
echo "Sequential transfer (1 transfer, 1 checker): ${SEQ_MS} ms"

echo "=== 2. Benchmarking Concurrent Transfer (--transfers 4, --checkers 8) ==="
START=$(date +%s%N)
rclone copy samples/source/documents :s3:testpress-source/bench-parallel \
  --config /dev/null --transfers 4 --checkers 8
END=$(date +%s%N)
PAR_MS=$(( (END - START) / 1000000 ))
echo "Concurrent transfer (4 transfers, 8 checkers): ${PAR_MS} ms"

echo "=== 3. Benchmarking Multi-Thread Streams on 100MB File ==="
START=$(date +%s%N)
rclone copy samples/source/media/module-01-preview.mp4 :s3:testpress-source/bench-stream1/ \
  --config /dev/null --multi-thread-streams 1
END=$(date +%s%N)
STREAM1_MS=$(( (END - START) / 1000000 ))
echo "Single-stream upload (100MB): ${STREAM1_MS} ms"

START=$(date +%s%N)
rclone copy samples/source/media/module-01-preview.mp4 :s3:testpress-source/bench-stream4/ \
  --config /dev/null --multi-thread-streams 4
END=$(date +%s%N)
STREAM4_MS=$(( (END - START) / 1000000 ))
echo "4-stream upload (100MB): ${STREAM4_MS} ms"