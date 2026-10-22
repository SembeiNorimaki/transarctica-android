import os

def extract_functions_from_gd(folder_path, output_file):
    results = []

    # Order in which declarations should appear in the output
    prefixes = [
        "@onready",
        "signal ",
        "const ",
        "var ",
        "func "
    ]

    for root, _, files in os.walk(folder_path):
        for filename in files:
            if filename.endswith(".gd"):
                full_path = os.path.join(root, filename)

                # Store lines separately by category
                extracted = {prefix: [] for prefix in prefixes}

                with open(full_path, "r", encoding="utf-8") as f:
                    for line in f:
                        stripped = line.lstrip().rstrip()

                        for prefix in prefixes:
                            if stripped.startswith(prefix):
                                extracted[prefix].append(stripped)
                                break

                results.append((filename, extracted))

    # Write output (overwrite existing contents)
    with open(output_file, "w", encoding="utf-8") as out:
        for filename, extracted in results:
            out.write(f"{filename}\n")

            for prefix in prefixes:
                for line in extracted[prefix]:
                    out.write(f"  {line}\n")

            # Blank line between files
            out.write("\n")


# Example usage
folder_path = r"C:/Users/Isaac/Documents/GitHub/transarctica-android/scripts"
output_file = r"C:/Users/Isaac/Documents/GitHub/transarctica-android/functions.txt"

extract_functions_from_gd(folder_path, output_file)



