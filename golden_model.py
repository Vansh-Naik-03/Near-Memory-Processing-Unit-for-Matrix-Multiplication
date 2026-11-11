#!/usr/bin/env python3
"""
golden_model.py
Project: Near-Memory Processing Unit (NMPU) for Matrix Multiplication
Description:
    Python Golden Model to generate signed test matrices A & B,
    compute golden reference C = A x B, and export hexadecimal
    files for Verilog $readmemh simulation verification.
"""

import os
import sys

def twos_complement_hex(val, bits=8):
    """Converts a signed integer to two's complement hex string."""
    if val < 0:
        val = (1 << bits) + val
    hex_len = (bits + 3) // 4
    return f"{val & ((1 << bits) - 1):0{hex_len}x}"

def generate_matrices(n=4):
    """
    Generates deterministic signed matrices A and B with positive,
    negative, zero, and boundary values to thoroughly test the PE core.
    """
    # Deterministic representative 4x4 matrices
    A = [
        [  3, -2,   4,  1],
        [  5,  0,  -3,  2],
        [ -1,  4,   2, -5],
        [  2, -1,   0,  3]
    ]

    B = [
        [  2,  1, -3,  4],
        [ -4,  3,  2,  0],
        [  1, -2,  5, -1],
        [  0,  4, -1,  2]
    ]

    # Compute golden reference C = A x B
    C = [[0 for _ in range(n)] for _ in range(n)]
    for i in range(n):
        for j in range(n):
            val = 0
            for k in range(n):
                val += A[i][k] * B[k][j]
            C[i][j] = val

    return A, B, C

def export_hex_files(out_dir, n, A, B, C):
    os.makedirs(out_dir, exist_ok=True)

    # Export Matrix A (8-bit signed)
    with open(os.path.join(out_dir, "a_data.hex"), "w") as f:
        for i in range(n):
            for j in range(n):
                f.write(twos_complement_hex(A[i][j], bits=8) + "\n")

    # Export Matrix B (8-bit signed)
    with open(os.path.join(out_dir, "b_data.hex"), "w") as f:
        for i in range(n):
            for j in range(n):
                f.write(twos_complement_hex(B[i][j], bits=8) + "\n")

    # Export Expected Result C (24-bit signed)
    with open(os.path.join(out_dir, "c_expected.hex"), "w") as f:
        for i in range(n):
            for j in range(n):
                f.write(twos_complement_hex(C[i][j], bits=24) + "\n")

    print(f"[INFO] Successfully generated hex test vectors in: {out_dir}")

def print_matrix(name, M):
    print(f"\n--- Matrix {name} ---")
    for row in M:
        print("  [" + ", ".join(f"{x:5d}" for x in row) + " ]")

if __name__ == "__main__":
    n = 4
    A, B, C = generate_matrices(n)

    print("==================================================")
    print("   NMPU Python Golden Model (Matrix Multiplication)")
    print("==================================================")
    print_matrix("A (4x4)", A)
    print_matrix("B (4x4)", B)
    print_matrix("C = A x B (Expected 4x4)", C)

    base_dir = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.join(base_dir, "test_vectors")
    export_hex_files(out_dir, n, A, B, C)
