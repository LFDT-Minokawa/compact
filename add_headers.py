# This file is part of Compact.
# Copyright (C) 2025 Midnight Foundation
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  	http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import json
import logging
import os
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, Pattern

# basic logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)


class HeaderManager:

    def __init__(self, config_path: str, directory: str):
        self.config = self._load_config(config_path)
        self.prefixes = self.config.get("prefixes", {})
        self.excluded_directories = self.config.get("excluded_directories", [])
        self.excluded_files = self.config.get("excluded_files", [])
        self.header_template = self.config.get("header_template", "")
        self.company_name = "Midnight Foundation"
        self.root_directory = directory
        self.processed_files = 0
        self.total_files = 0
        # Cache compiled regex patterns
        self._header_patterns: Dict[str, Pattern] = {}

    @staticmethod
    def _load_config(config_path: str) -> Dict:
        try:
            with open(config_path, 'r', encoding='utf-8') as file:
                return json.load(file)
        except (json.JSONDecodeError, FileNotFoundError) as e:
            logging.error("-> error loading configuration: %s", e)
            return {}

    def _filter_files_and_directories(self) -> list[Path]:
        result = []

        for dir_path, dir_names, filenames in os.walk(self.root_directory):
            # Filter directories in-place
            dir_names[:] = [d for d in dir_names if d not in self.excluded_directories]

            # Only collect files, not directories
            for filename in filenames:
                if filename not in self.excluded_files:
                    result.append(Path(dir_path) / filename)

        return result

    def _filter_extensions(self) -> Dict[str, list[Path]]:
        filtered_files = self._filter_files_and_directories()
        filtered_dictionary = {}

        for prefix, content in self.prefixes.items():
            extensions = content.get("extensions", [])
            special_cases = content.get("special_cases", [])

            temp_filtered_files = [
                f for f in filtered_files
                if f.suffix in extensions or f.name in special_cases
            ]
            filtered_dictionary[prefix] = temp_filtered_files

        return filtered_dictionary

    def _format_license_header(self, prefix: str, year: str) -> str:
        filled = self.header_template.replace("[YEAR]", year).replace("[COMPANY]", self.company_name)
        return '\n'.join(f"{prefix} {line}" if line else prefix for line in filled.splitlines())

    def _get_header_pattern(self, prefix: str) -> Pattern:
        """Build and cache regex pattern for header detection"""
        if prefix in self._header_patterns:
            return self._header_patterns[prefix]

        template_lines = self.header_template.strip().splitlines()
        regex_lines = []

        for line in template_lines:
            escaped = re.escape(line)
            escaped = escaped.replace(r"\[YEAR\]", r"\d{4}")
            escaped = escaped.replace(r"\[COMPANY\]", re.escape(self.company_name))

            # Empty lines become just the prefix, non-empty lines have prefix + whitespace + content
            if line:
                # Strip leading whitespace from template line and make it flexible
                line_stripped = line.lstrip()
                escaped_stripped = re.escape(line_stripped)
                escaped_stripped = escaped_stripped.replace(r"\[YEAR\]", r"\d{4}")
                escaped_stripped = escaped_stripped.replace(r"\[COMPANY\]", re.escape(self.company_name))
                # Match prefix + one or more whitespace + content (flexible whitespace)
                regex_lines.append(re.escape(prefix) + r"\s+" + escaped_stripped)
            else:
                # Empty lines: prefix with optional trailing whitespace
                regex_lines.append(re.escape(prefix) + r"\s*")

        full_pattern = r"\n".join(regex_lines)
        pattern = re.compile(full_pattern, re.MULTILINE)
        self._header_patterns[prefix] = pattern
        return pattern

    def _scan_for_header(self, prefix: str, content: str) -> bool:
        pattern = self._get_header_pattern(prefix)
        return bool(pattern.search(content))

    @staticmethod
    def _get_insert_index(lines: list[str]) -> int:
        index = 0
        while index < len(lines) and lines[index].startswith("#!"):
            index += 1
        return index

    def _save_header_to_file(self, prefix: str, file_path: Path, header: str):
        try:
            content = file_path.read_text(encoding='utf-8', errors='ignore')

            if self._scan_for_header(prefix, content):
                logging.debug(f"-> header already exists: {file_path}")
                return

            lines = content.splitlines()
            insert_index = self._get_insert_index(lines)

            new_lines = []

            # preserve shebang
            if insert_index > 0:
                new_lines.extend(lines[:insert_index])
                new_lines.append("")

            # header
            new_lines.extend(header.strip().splitlines())

            # ensure empty line after header
            if insert_index < len(lines) and lines[insert_index].strip():
                new_lines.append("")

            new_lines.extend(lines[insert_index:])

            file_path.write_text('\n'.join(new_lines) + '\n', encoding='utf-8')
            logging.info(f"-> header added to: {file_path}")
            self.processed_files += 1

        except (OSError, UnicodeDecodeError) as e:
            logging.error(f"-> failed to process: {file_path}: {e}")

    def add_headers(self):
        filtered_files = self._filter_extensions()
        current_year = str(datetime.now().year)

        for prefix, files in filtered_files.items():
            # Build header once per prefix group
            header = self._format_license_header(prefix, current_year)

            for file in files:
                self.total_files += 1
                self._save_header_to_file(prefix, file, header)

        logging.info(f"-> total files: {self.total_files}")
        logging.info(f"-> processed files: {self.processed_files}")

    def validate_headers(self) -> list[Path]:
        """
        Check which files are missing headers without modifying them.
        Returns list of files missing headers (empty list = all good).
        """
        filtered_files = self._filter_extensions()
        missing_headers = []

        for prefix, files in filtered_files.items():
            for file in files:
                self.total_files += 1
                try:
                    content = file.read_text(encoding='utf-8', errors='ignore')
                    if not self._scan_for_header(prefix, content):
                        missing_headers.append(file)
                        logging.warning(f"-> missing header: {file}")
                except (OSError, UnicodeDecodeError) as e:
                    logging.error(f"-> failed to read: {file}: {e}")

        logging.info(f"-> total files checked: {self.total_files}")
        logging.info(f"-> files missing headers: {len(missing_headers)}")

        return missing_headers


def main():
    import sys

    header_manager = HeaderManager("header_config.json", ".")

    # Check if --validate flag is passed
    if len(sys.argv) > 1 and sys.argv[1] == "--validate":
        missing = header_manager.validate_headers()
        if missing:
            logging.error(f"❌ {len(missing)} file(s) missing headers")
            for file in missing:
                print(f"  - {file}")
            sys.exit(1)  # Exit with error code for CI
        else:
            logging.info("✅ All files have headers")
            sys.exit(0)
    else:
        header_manager.add_headers()


if __name__ == "__main__":
    main()