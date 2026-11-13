#!/usr/bin/env python3
"""
systolic_golden_model.py
Project: Near-Memory Processing Unit (NMPU) for Matrix Multiplication
Description:
    Python Golden Model for the 2D 4x4 Output-Stationary Systolic Array.
    Independently of the existing golden_model.py (which uses a signed test matrix),
    this script:
      1. Verifies the fixed-point (8-bit signed × 8-bit signed → 24-bit signed) arithmetic.
      2. Simulates the temporal skew schedule cycle-by-cycle.
      3. Generates hex test vector files for FOUR distinct matrix test cases:
            test_vectors/sys_1to16_a.hex / _b.hex / _c.hex   (1..16 × 1..16)
            test_vectors/sys_signed_a.hex / _b.hex / _c.hex   (signed/zero, same as golden_model.py)
            test_vectors/sys_identity_a.hex / _b.hex / _c.hex (identity × signed)
            test_vectors/sys_extreme_a.hex / _b.hex / _c.hex  (-128/127/0 matrix)
      4. Prints cycle-by-cycle systolic wavefront trace for the first test case.
"""

import os
import sys

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------
def to_signed8(val):
    """Clamp and interpret as 8-bit signed integer."""
    val = int(val) & 0xFF
    return val - 256 if val >= 128 else val

def to_signed24(val):
    """Interpret as 24-bit signed integer."""
    val = int(val) & 0xFFFFFF
    return val - (1 << 24) if val >= (1 << 23) else val

def twos_hex(val, bits):
    """Return two's complement hex string of val in given bit-width."""
    mask = (1 << bits) - 1
    nib  = (bits + 3) // 4
    return f"{val & mask:0{nib}x}"

# ---------------------------------------------------------------------------
# Matrix multiply (reference, no bit-width constraints)
# ---------------------------------------------------------------------------
def matmul(A, B, N=4):
    C = [[0]*N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            for k in range(N):
                C[i][j] += A[i][k] * B[k][j]
    return C

# ---------------------------------------------------------------------------
# Cycle-accurate systolic wavefront simulator
# ---------------------------------------------------------------------------
def simulate_systolic_wavefront(A, B, N=4, verbose=False):
    """
    Simulates the 2D output-stationary systolic array cycle-by-cycle using
    the same skew schedule as systolic_input_feeder.v:
        A[i][k] enters row i at feeder cycle t = k + i
        B[k][j] enters col j at feeder cycle t = k + j

    Feeder output is REGISTERED (1-cycle pipeline register), so array sees
    feeder output from cycle t at posedge T+1 (where T = t+1 relative to
    feeder_enable going high).

    PE forwarding adds 1 cycle per hop:
        A[i][k] enters PE(i,0) at array edge P = t+2 = k+i+2
        A[i][k] reaches PE(i,j) at P = k+i+j+2
        B[k][j] enters PE(0,j) at array edge P = t+2 = k+j+2
        B[k][j] reaches PE(i,j) at P = k+i+j+2   ← same cycle ✓

    Returns the N×N accumulator matrix C and a list of trace events.
    """
    # PE state
    acc       = [[0]*N for _ in range(N)]
    a_pipe    = [[0]*N for _ in range(N)]   # a_out registers
    b_pipe    = [[0]*N for _ in range(N)]   # b_out registers
    a_val     = [[False]*N for _ in range(N)]
    b_val     = [[False]*N for _ in range(N)]

    # Feeder output registers (1-cycle delay from decision)
    fa_out   = [0]*N;  fb_out = [0]*N
    fa_valid = [False]*N; fb_valid = [False]*N

    TOTAL_FEED = 2*N - 1    # 7 cycles  (t = 0..6)
    DRAIN      = N          # 4 extra cycles for wavefront to clear

    events = []
    max_cycles = TOTAL_FEED + DRAIN + 2

    for edge in range(1, max_cycles + 1):
        t = edge - 1          # feeder cycle to drive at this edge

        # --- Compute new feeder outputs for this edge ---
        new_fa = [0]*N; new_fb = [0]*N
        new_fa_v = [False]*N; new_fb_v = [False]*N
        if 0 <= t < TOTAL_FEED:
            for row in range(N):
                if row <= t < row + N:
                    k = t - row
                    new_fa[row]   = A[row][k]
                    new_fa_v[row] = True
            for col in range(N):
                if col <= t < col + N:
                    k = t - col
                    new_fb[col]   = B[k][col]
                    new_fb_v[col] = True

        # --- Update array: sample PREVIOUS feeder outputs ---
        # Boundary: row r left input = fa_out[r] (from PREVIOUS edge)
        new_a_pipe = [[0]*N for _ in range(N)]
        new_b_pipe = [[0]*N for _ in range(N)]
        new_a_val  = [[False]*N for _ in range(N)]
        new_b_val  = [[False]*N for _ in range(N)]

        for r in range(N):
            for c in range(N):
                # What does PE(r,c) see at its inputs?
                a_in_val = fa_valid[r] if c == 0 else a_val[r][c-1]
                a_in_dat = fa_out[r]   if c == 0 else a_pipe[r][c-1]
                b_in_val = fb_valid[c] if r == 0 else b_val[r-1][c]
                b_in_dat = fb_out[c]   if r == 0 else b_pipe[r-1][c]

                # Register forwarding
                new_a_pipe[r][c] = a_in_dat
                new_b_pipe[r][c] = b_in_dat
                new_a_val[r][c]  = a_in_val
                new_b_val[r][c]  = b_in_val

                # Accumulate
                if a_in_val and b_in_val:
                    prod = to_signed8(a_in_dat) * to_signed8(b_in_dat)
                    acc[r][c] += prod
                    if verbose:
                        events.append(
                            f"  Edge {edge:2d}: PE({r},{c}) += "
                            f"A[{r}][?]={to_signed8(a_in_dat):4d} × "
                            f"B[?][{c}]={to_signed8(b_in_dat):4d} = {prod:6d} "
                            f"(acc={acc[r][c]:7d})"
                        )

        # Commit new state
        a_pipe = new_a_pipe;  b_pipe = new_b_pipe
        a_val  = new_a_val;   b_val  = new_b_val
        fa_out = new_fa;      fb_out = new_fb
        fa_valid = new_fa_v;  fb_valid = new_fb_v

    return acc, events

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------
def build_test_cases(N=4):
    cases = {}

    # Test 1: sequential 1..16
    A1 = [[i*N + j + 1 for j in range(N)] for i in range(N)]
    B1 = [[i*N + j + 1 for j in range(N)] for i in range(N)]
    cases["1to16"] = (A1, B1)

    # Test 2: signed/zero matrix (same as golden_model.py)
    A2 = [[3,-2,4,1],[5,0,-3,2],[-1,4,2,-5],[2,-1,0,3]]
    B2 = [[2,1,-3,4],[-4,3,2,0],[1,-2,5,-1],[0,4,-1,2]]
    cases["signed"] = (A2, B2)

    # Test 3: identity × signed matrix
    I = [[1 if i==j else 0 for j in range(N)] for i in range(N)]
    cases["identity"] = (I, A2)

    # Test 4: extreme signed values (-128, 127, 0 alternating)
    A4 = [[-128 if (i+j)%2==0 else 0 for j in range(N)] for i in range(N)]
    B4 = [[-128 if (i+j)%2==0 else 127 for j in range(N)] for i in range(N)]
    cases["extreme"] = (A4, B4)

    return cases

# ---------------------------------------------------------------------------
# Export hex vectors
# ---------------------------------------------------------------------------
def export_hex(out_dir, name, A, B, C, N=4):
    os.makedirs(out_dir, exist_ok=True)
    flat = lambda M: [M[i][j] for i in range(N) for j in range(N)]

    for tag, data, bits in [("a", flat(A), 8), ("b", flat(B), 8), ("c", flat(C), 24)]:
        path = os.path.join(out_dir, f"sys_{name}_{tag}.hex")
        with open(path, "w") as f:
            for v in data:
                f.write(twos_hex(v, bits) + "\n")
        print(f"  Wrote {path}")

# ---------------------------------------------------------------------------
# Pretty print
# ---------------------------------------------------------------------------
def print_mat(label, M):
    print(f"  {label}:")
    for row in M:
        print("    [" + "  ".join(f"{v:5d}" for v in row) + " ]")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    N = 4
    base  = os.path.dirname(os.path.abspath(__file__))
    # Place test vectors in the project-root test_vectors/ folder
    out_dir = os.path.join(base, "..", "test_vectors")

    print("=" * 60)
    print("  Systolic Array Python Golden Model")
    print("  Cycle-Accurate Skew Simulation + Hex Vector Export")
    print("=" * 60)

    cases = build_test_cases(N)
    all_ok = True

    for name, (A, B) in cases.items():
        C_ref  = matmul(A, B, N)
        C_sys, events = simulate_systolic_wavefront(A, B, N, verbose=(name=="1to16"))

        # Verify systolic vs reference
        ok = all(C_sys[i][j] == C_ref[i][j] for i in range(N) for j in range(N))
        status = "PASS" if ok else "FAIL"
        if not ok:
            all_ok = False

        print(f"\n[{status}] Test case: {name}")
        print_mat("A", A)
        print_mat("B", B)
        print_mat("C = A×B (reference)", C_ref)
        print_mat("C (systolic sim)", C_sys)

        if name == "1to16" and events:
            print(f"\n  Cycle-by-cycle wavefront trace (first 8 / last 4 events):")
            for e in events[:8]:
                print(e)
            if len(events) > 12:
                print("  ...")
            for e in events[-4:]:
                print(e)

        export_hex(out_dir, name, A, B, C_ref, N)

    print()
    print("=" * 60)
    if all_ok:
        print("  ALL GOLDEN MODEL CHECKS PASSED (100% bit-accurate)")
    else:
        print("  GOLDEN MODEL MISMATCH DETECTED")
    print("=" * 60)
    sys.exit(0 if all_ok else 1)

