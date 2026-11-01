#!/usr/bin/env python3
"""
Test Dataset Generator for Rclone Automation Experiments
Creates nested directory structures, text documents, PDFs, a 100MB video asset, and a 1GB lecture asset.
"""

import os
from pathlib import Path

BASE_DIR = Path("/home/hp2/workspace/rclone-storage-automation/samples")
SOURCE_DIR = BASE_DIR / "source"
DEST_DIR = BASE_DIR / "destination"

def generate_file(path: Path, size_bytes: int, fill_pattern: bytes = b"A"):
    path.parent.mkdir(parents=True, exist_ok=True)
    chunk_size = 1024 * 1024  # 1 MB chunk
    num_chunks = size_bytes // chunk_size
    remainder = size_bytes % chunk_size

    pattern = fill_pattern * chunk_size

    with open(path, "wb") as f:
        for _ in range(num_chunks):
            f.write(pattern)
        if remainder > 0:
            f.write(fill_pattern * remainder)
    print(f"Created: {path} ({size_bytes / (1024*1024):.2f} MB)")

def main():
    print("Generating sample test datasets...")
    
    # 1. Nested Text Documents
    doc_dir = SOURCE_DIR / "documents"
    doc_dir.mkdir(parents=True, exist_ok=True)
    
    with open(doc_dir / "notes.txt", "w") as f:
        f.write("Testpress Rclone automation study notes.\nStorage workflows and large file transfers.")
        
    with open(doc_dir / "manifest.json", "w") as f:
        f.write('{\n  "course_id": 101,\n  "title": "Cloud Storage Automation",\n  "status": "published"\n}')

    with open(doc_dir / "curriculum.md", "w") as f:
        f.write("# Curriculum\n1. S3 Object Storage\n2. Rclone CLI\n3. High Reliability Transfers\n")

    # 2. PDF Documents (simulated with PDF header)
    pdf_dir = SOURCE_DIR / "documents" / "pdf"
    pdf_dir.mkdir(parents=True, exist_ok=True)
    
    for i in range(1, 4):
        pdf_path = pdf_dir / f"lecture-{i}-guide.pdf"
        header = b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n"
        generate_file(pdf_path, 2 * 1024 * 1024, fill_pattern=bytes([i + 60]))

    # 3. Media folder with 100 MB test file
    media_dir = SOURCE_DIR / "media"
    generate_file(media_dir / "module-01-preview.mp4", 100 * 1024 * 1024, fill_pattern=b"V")

    # 4. Large 1 GB test file for Phase 5 transfers
    large_dir = SOURCE_DIR / "large"
    generate_file(large_dir / "course-archive-1gb.bin", 1024 * 1024 * 1024, fill_pattern=b"X")

    print("\nDataset generation completed successfully.")

if __name__ == "__main__":
    main()
