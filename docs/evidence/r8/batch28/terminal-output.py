"""Produce numbered, short lines for a bounded scrollback test in an isolated terminal."""
import time

for n in range(1, 101):
    print(f"LINE {n:04}")
input("Press Enter for 40 seconds of output. ")
for batch in range(160):
    for n in range(101 + batch * 10, 111 + batch * 10):
        print(f"LINE {n:04}")
    print("", end="", flush=True)
    time.sleep(0.25)
print("OUTPUT COMPLETE 1700", flush=True)
