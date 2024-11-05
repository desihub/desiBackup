#!/usr/bin/env python3
"""Previous imports remain the same, adding new ones"""
import os
import subprocess
import argparse
import datetime
import json
from pathlib import Path
import logging
from typing import Dict, List, Tuple, Optional
from concurrent.futures import ThreadPoolExecutor
import re
import glob
import math
import String_shorter as sshort

class HSIException(Exception):
    """Custom exception for HSI-related errors"""
    pass

class TapeOperations:
    """Helper class for HSI tape operations"""

    @staticmethod
    def run_hsi_command(command: str, check: bool = True) -> subprocess.CompletedProcess:
        """
        Run an HSI command and return the result

        Args:
            command: HSI command to run
            check: If True, raise exception on non-zero return code

        Returns:
            CompletedProcess instance
        """
        full_command = f"hsi {command}"
        try:
            result = subprocess.run(full_command, shell=True, check=check,
                                  capture_output=True, text=True)
            return result
        except subprocess.CalledProcessError as e:
            raise HSIException(f"HSI command failed: {e.stderr}")

    @classmethod
    def check_path_exists(cls, path: str) -> bool:
        """Check if a path exists on tape"""
        try:
            result = cls.run_hsi_command(f"ls -l {path}")
            return "not found" not in result.stderr.lower()
        except HSIException:
            return False

    @classmethod
    def create_directory(cls, path: str) -> bool:
        """Create directory on tape system"""
        try:
            cls.run_hsi_command(f"mkdir -p {path}")
            return True
        except HSIException as e:
            logging.error(f"Failed to create directory {path}: {e}")
            return False

    @classmethod
    def create_archive_directory(cls, path: str) -> bool:
        """
        Create an archive directory and all its parent directories on tape if they don't exist.

        Args:
            path: The full path of the archive directory to create

        Returns:
            bool: True if directory creation was successful, False otherwise

        Example:
            TapeOperations.create_archive_directory('/archive/2024/01/dataset')
        """
        try:
            # Normalize the path to remove any trailing slashes
            path = path.rstrip('/')

            # Split the path into components
            components = path.split('/')

            # Start with the root directory
            current_path = ''

            # Iterate through path components and create directories as needed
            for component in components:
                if not component:  # Skip empty components
                    continue

                # Build the path incrementally
                current_path = f"{current_path}/{component}"

                # Check if the current level exists
                if not cls.check_path_exists(current_path):
                    logging.info(f"Creating directory: {current_path}")
                    try:
                        # Create single directory (not using -p flag here since we're doing it manually)
                        result = cls.run_hsi_command(f"mkdir {current_path}")
                        if "not created" in result.stderr.lower():
                            logging.error(f"Failed to create directory {current_path}")
                            return False
                    except HSIException as e:
                        logging.error(f"Error creating directory {current_path}: {e}")
                        return False
                else:
                    logging.debug(f"Directory already exists: {current_path}")

            # Verify final path exists
            if cls.check_path_exists(path):
                logging.info(f"Successfully created archive directory structure: {path}")
                return True
            else:
                logging.error(f"Failed to verify created directory structure: {path}")
                return False

        except Exception as e:
            logging.error(f"Unexpected error creating archive directory structure {path}: {e}")
            return False

    @classmethod
    def list_directory(cls, path: str) -> List[Dict[str, str]]:
        """
        List contents of a directory on tape
        Returns list of dicts with file info
        """
        try:
            result = cls.run_hsi_command(f"ls -l {path}")
            files = []
            for line in result.stdout.splitlines():
                if line.startswith('d') or line.startswith('-'):
                    parts = line.split()
                    if len(parts) >= 9:
                        files.append({
                            'type': 'directory' if line.startswith('d') else 'file',
                            'permissions': parts[0],
                            'size': parts[4],
                            'date': f"{parts[5]} {parts[6]} {parts[7]}",
                            'name': parts[8]
                        })
            return files
        except HSIException as e:
            logging.error(f"Failed to list directory {path}: {e}")
            return []

    @classmethod
    def verify_tape_file(cls, path: str) -> Optional[Dict[str, str]]:
        """
        Verify a file exists on tape and return its details
        Returns None if file not found or error occurs
        """
        try:
            result = cls.run_hsi_command(f"ls -l {path}")
            for line in result.stdout.splitlines():
                if line.startswith('-'):  # Regular file
                    parts = line.split()
                    if len(parts) >= 9:
                        return {
                            'size': parts[4],
                            'date': f"{parts[5]} {parts[6]} {parts[7]}",
                            'name': parts[8]
                        }
            return None
        except HSIException:
            return None

class DataArchiver:
    def __init__(self, root_dir: str, archive_root: str, chunk_size: int = 20480, create_archive: bool = False):
        """
        Initialize the archiver
        root_dir: Source directory containing data to archive
        archive_root: Target directory on tape system
        chunk_size: Maximum size in GB for each archive chunk (default 20480 GB = 20 TB)
        create_archive: If True, submit archive jobs; if False, dry run only
        """
        self.root_dir_str = root_dir
        self.root_dir = Path(self.root_dir_str)
        self.archive_root_str = archive_root
        self.archive_root = Path(self.archive_root_str)
        # Convert GB to bytes for internal use
        self.chunk_size_bytes = chunk_size * 1024 * 1024 * 1024
        # The max limit should be 68Gb but sometimes 67.7GB file also failed so setting this to 67
        self.max_htar_size = 67 * 1024 * 1024 * 1024  # 68 GB in bytes
        self.max_htar_prefix = 154 #maximum size of prefix in htar
        self.max_htar_fname = 99  # maximum size of filename in htar
        self.create_archive = create_archive
        self.manifest = {}
        self.setup_logging()

        # Create documentation directory
        self.doc_dir = self.root_dir / "docs"
        #doc_dir = self.archive_root / "docs"
        self.doc_dir.mkdir(parents=True, exist_ok=True)
        #if not self.tape_ops.check_path_exists(doc_dir):
        #any file split its information will be stored here
        self.split_file=f'{self.doc_dir}/split_file.json'
        self.large_path_file=f'{self.doc_dir}/large_path_file.json'
        # Initialize tape operations
        self.tape_ops = TapeOperations()
        
        if self.create_archive:
            # Verify/create archive directory on tape
            if not self.tape_ops.check_path_exists(str(self.archive_root)):
                if not self.tape_ops.create_directory(str(self.archive_root)):
                    raise HSIException(f"Failed to create archive directory: {self.archive_root}")

    def get_directory_tree(self) -> Dict[str, int]:
        """
        Get complete directory tree with sizes using du command
        Returns dictionary of directory paths and their sizes in bytes
        """
        logging.info("Scanning complete directory structure...")

        # Use du without depth limitation
        cmd = f"du -b {self.root_dir}"
        try:
            result = subprocess.run(cmd, shell=True, check=True,
                                 capture_output=True, text=True)
            sizes = {}
            for line in result.stdout.splitlines():
                size, path = line.split('\t')
                sizes[path] = int(size)
            return sizes
        except subprocess.CalledProcessError as e:
            logging.error(f"Error running du command: {e}")
            raise

    def get_files_in_directory(self, directory: str, min_size: int = 0) -> List[Tuple[str, int]]:
        """
        Get files and their sizes in a directory using find command
        min_size: Minimum file size in bytes to consider
        """
        #converts the min_size from bytes to GB
        min_size_GB=int(min_size/(1024*1024*1024))
        # Use find command to get all files with their sizes
        cmd = f"find {directory} -type f -printf '%s %p\\n'"
        if min_size > 0:
            cmd = f"find {directory} -type f -size +{min_size_GB}G -printf '%s %p\\n'"

        try:
            result = subprocess.run(cmd, shell=True, check=True,
                                 capture_output=True, text=True)

            files = []
            for line in result.stdout.splitlines():
                if not line.strip():
                    continue
                try:
                    size, path = line.split(' ', 1)
                    files.append((path.strip(), int(size)))
                except ValueError:
                    logging.warning(f"Couldn't parse line: {line}")
                    continue

            return files
        except subprocess.CalledProcessError as e:
            logging.error(f"Error listing directory {directory}: {e}")
            return []

    def parallel_scan_large_directory(self, num_workers: int = 8) -> Dict[str, int]:
        """Scan directory structure in parallel"""
        # Get complete directory tree first
        dir_sizes = self.get_directory_tree()
        logging.info(f"Found {len(dir_sizes)} directories")

        # Sort directories by size
        sorted_dirs = sorted(dir_sizes.items(), key=lambda x: x[1], reverse=True)

        # For very large directories, process them in parallel
        # Consider directories larger than 1% of chunk size as "large"
        if(False):
            size_threshold = self.chunk_size_bytes * 0.01
            large_dirs = [(path, size) for path, size in sorted_dirs
                     if size > size_threshold]

            small_dirs = [(path, size) for path, size in sorted_dirs
                     if size <= size_threshold]
        else:
            large_dirs=[]
            small_dirs=sorted_dirs

        logging.info(f"Processing {len(large_dirs)} large directories in parallel")
        logging.info(f"Will process {len(small_dirs)} smaller directories sequentially")

        file_sizes = {}

        # Process large directories in parallel
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            future_to_dir = {
                executor.submit(self.get_files_in_directory, dir_path, size_threshold): dir_path
                for dir_path, _ in large_dirs
            }

            for future in future_to_dir:
                dir_path = future_to_dir[future]
                try:
                    for file_path, size in future.result():
                        file_sizes[file_path] = size
                except Exception as e:
                    logging.error(f"Error processing directory {dir_path}: {e}")

        # Process smaller directories sequentially
        for dir_path, _ in small_dirs:
            try:
                for file_path, size in self.get_files_in_directory(dir_path):
                    file_sizes[file_path] = size
            except Exception as e:
                logging.error(f"Error processing directory {dir_path}: {e}")

        return file_sizes

    def setup_logging(self):
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(lineno)d - %(message)s',
            handlers=[
                logging.FileHandler('archive_process.log'),
                logging.StreamHandler()
            ]
        )


    def get_directory_sizes(self, max_depth: int = 10) -> Dict[str, int]:
        """
        Get directory sizes efficiently using du command
        Returns dictionary of directory paths and their sizes in bytes
        """
        logging.info(f"Scanning directory structure (max depth: {max_depth})")

        # Use du command with max depth to get directory sizes
        cmd = f"du -b --max-depth={max_depth} {self.root_dir}"
        try:
            result = subprocess.run(cmd, shell=True, check=True,
                                 capture_output=True, text=True)
            sizes = {}
            for line in result.stdout.splitlines():
                size, path = line.split('\t')
                sizes[path] = int(size)
            return sizes
        except subprocess.CalledProcessError as e:
            logging.error(f"Error running du command: {e}")
            raise

    def Shorten_path(self,file_path:str,large_path_dir='large_path_files'):
        '''Takes the full path and split it in 
        root_dir + rest_dir + file_name
        create a directory called large_path_files
        It creates a new path as 
        root_dir/large_path_files/file_name.code(res_dir)
        copy the file to new location and returns the path
        '''
         
        rel_path=file_path[len(self.root_dir_str):]
        fname=rel_path.split('/')[-1]
        #Determine the length of two component 
        fname_len =len(fname)
        prefix_len=len(file_path)-fname_len

        rest_dir=rel_path[:-fname_len]
        need_short=False
        #shorten prefix and filename if needed
        if(prefix_len>=self.max_htar_prefix or fname_len>=self.max_htar_fname):
            short_prefix=f"{self.root_dir_str}/{large_path_dir}/"
            # Create directory for split files if it doesn't exist
            #large_dir = f"{self.root_dir}/{large_path_dir}/" 
            large_dir = self.root_dir / large_path_dir
            large_dir.mkdir(exist_ok=True)
            short_fname=sshort.string_to_short_code(rel_path, max_length=64,preserve_extension=True)
            new_path=f"{short_prefix}{short_fname}"

            need_short=True
        else:
            new_path=None


        #copy file to new location
        if(need_short):
            cmd='cp %s %s'%(file_path,new_path)
            result = subprocess.run(cmd, shell=True, check=True,
                                 capture_output=True, text=True)
            #print('copying large file: %s \n -> \n %s'%(file_path,new_path))


        return {'path':file_path,'short_path':new_path}, need_short



    def split_large_file(self, file_path: str) -> List[str]:
        """
        Split a file larger than 68GB into smaller chunks
        Returns list of split file paths
        """
        file_size = Path(file_path).stat().st_size
        if file_size <= self.max_htar_size:
            return [file_path]

        # Calculate number of chunks needed
        num_chunks = math.ceil(file_size / self.max_htar_size)
        chunk_size = math.ceil(file_size / num_chunks)
        split_files = []
        
        # Create directory for split files if it doesn't exist
        split_dir = self.root_dir / "split_files"
        split_dir.mkdir(exist_ok=True)
        
        base_name = Path(file_path).name
        # Use split command to create chunks
        split_base = split_dir / f"{base_name}.split"
        try:
            cmd = f"split -b {chunk_size} -d '{file_path}' '{split_base}'"
            subprocess.run(cmd, shell=True, check=True)
            
            # Get list of split files
            split_files = sorted(glob.glob(f"{split_base}*"))
            
            # Create manifest for reconstruction
            #manifest_path = split_dir / f"{base_name}.manifest"
            with open(self.split_file, 'a') as f:
                json.dump({
                    'original_file': str(file_path),
                    'original_size': file_size,
                    'chunk_size': chunk_size,
                    'num_chunks': num_chunks,
                    'split_files': split_files
                }, f, indent=2)
            
            logging.info(f"Split {file_path} into {len(split_files)} chunks")
            return split_files
            
        except subprocess.CalledProcessError as e:
            logging.error(f"Error splitting file {file_path}: {e}")
            return [file_path]

    def group_files_into_chunks(self, file_sizes: Dict[str, int]) -> List[List[str]]:
        """Group files into chunks respecting max chunk size, splitting large files if needed"""
        chunks = []
        current_chunk = []
        current_size = 0

        # Sort files by size in descending order for better packing
        sorted_files = sorted(file_sizes.items(), key=lambda x: x[1], reverse=True)

        for file_path_orig, size in sorted_files:
            #handle file path larger than htar limit
            short_dic,need_short=self.Shorten_path(file_path_orig)
            if(need_short):
                file_path=short_dic['short_path']
                with open(self.large_path_file, 'a') as f:
                    json.dump(short_dic, f, indent=2)
            else:
                file_path=file_path_orig
            # Handle files larger than HTAR limit
            if size > self.max_htar_size:
                # If there are files in current chunk, add it to chunks
                #if current_chunk:
                #    chunks.append(current_chunk)
                #    current_chunk = []
                #    current_size = 0
                
                # Split the large file
                split_files = self.split_large_file(file_path)
                
                # Add each split file to appropriate chunks
                for split_file in split_files:
                    split_size = Path(split_file).stat().st_size
                    if current_size + split_size > self.chunk_size_bytes:
                        if current_chunk:
                            chunks.append(current_chunk)
                        current_chunk = [split_file]
                        current_size = split_size
                    else:
                        current_chunk.append(split_file)
                        current_size += split_size
                continue

            # Regular file handling
            if current_size + size > self.chunk_size_bytes:
                if current_chunk:
                    chunks.append(current_chunk)
                current_chunk = [file_path]
                current_size = size
            else:
                current_chunk.append(file_path)
                current_size += size

        if current_chunk:
            chunks.append(current_chunk)

        return chunks

    def check_existing_archives(self) -> Dict[str, str]:
        """
        Check for existing archives and return mapping of archived files
        Returns: Dict[file_path: archive_path]
        """
        existing_files = {}
        manifest_path = self.archive_root / "archive_manifest.txt"
        
        # Check manifest on tape
        if not self.tape_ops.verify_tape_file(str(manifest_path)):
            return existing_files

        # Get manifest from tape
        try:
            temp_manifest = "archive_manifest.txt"
            self.tape_ops.run_hsi_command(f"get {manifest_path}")
            
            with open(temp_manifest, 'r') as f:
                for line in f:
                    archive_path, files = line.strip().split(':', 1)
                    # Verify archive exists on tape
                    if self.tape_ops.verify_tape_file(archive_path):
                        for file_path in files.split(','):
                            existing_files[file_path] = archive_path
                    else:
                        logging.warning(f"Listed archive not found on tape: {archive_path}")
            
            os.remove(temp_manifest)
        except Exception as e:
            logging.error(f"Error reading manifest from tape: {e}")
            if os.path.exists(temp_manifest):
                os.remove(temp_manifest)

        return existing_files

    def verify_archive_contents(self, archive_path: str, expected_files: List[str]) -> bool:
        """Verify archive contents match expected files"""
        try:
            # First verify archive exists on tape
            if not self.tape_ops.verify_tape_file(archive_path):
                logging.error(f"Archive not found on tape: {archive_path}")
                return False
                
            result = subprocess.run(['htar', '-tvf', archive_path], 
                                 capture_output=True, text=True, check=True)
            archived_files = set(line.split()[-1] for line in result.stdout.splitlines()[1:])
            expected_files_set = set(expected_files)
            return archived_files == expected_files_set
        except subprocess.CalledProcessError as e:
            logging.error(f"Error verifying archive {archive_path}: {e}")
            return False


    def create_slurm_script(self, chunk_id: int, files: List[str]) -> str:
        """Create a Slurm script for archiving a chunk of files"""
        timestamp = datetime.datetime.now().strftime("%Y%m%d")
        archive_name = f"archive_chunk_{chunk_id}_{timestamp}.tar"
        archive_path = self.archive_root / archive_name

        # Calculate estimated size for job requirements
        total_size = sum(Path(f).stat().st_size for f in files)
        mem_required = 45  # Keep the fixed memory requirement

        # Identify split files in this chunk
        split_files = [f for f in files if '.split' in str(f)]
        
        # Create file list file outside of the script
        chunk_files = f"{self.doc_dir}/chunk_{chunk_id}_files.txt"
        manifest_files = f"{self.root_dir}/chunk_{chunk_id}_manifests.txt"
        
        with open(chunk_files, 'w') as f:
            for file_path in files:
                f.write(f"{file_path}\n")
        
        # Create list of split file manifests
        #with open(manifest_files, 'w') as f:
        #    for split_file in split_files:
        #        base_name = Path(split_file).name.split('.split')[0]
        #        manifest_path = self.root_dir / "split_files" / f"{base_name}.manifest"
        #        if manifest_path.exists():
        #            f.write(f"{manifest_path}\n")

        script_content = f"""#!/bin/bash
#SBATCH --job-name=archive_chunk_{chunk_id}
#SBATCH --time=24:00:00
#SBATCH --qos=xfer
#SBATCH --constraint=cron
#SBATCH --mem={mem_required}G
#SBATCH --output=archive_chunk_{chunk_id}_%j.out
#SBATCH --error=archive_chunk_{chunk_id}_%j.err

cd {self.root_dir}

# File list is pre-created: {chunk_files}
if [ ! -f "{chunk_files}" ]; then
    echo "Error: File list not found: {chunk_files}"
    exit 1
fi

# Verify archive directory exists on tape
if ! hsi ls -l {self.archive_root}; then
    hsi mkdir -p {self.archive_root}
fi

# Check if archive already exists
if hsi ls -l {archive_path} > /dev/null 2>&1; then
    echo "Archive already exists: {archive_path}"
    exit 1
fi

# Create HTAR archive using file list
htar -cvf {archive_path} -L {chunk_files}

# Also archive split file manifests if they exist
if [ -f "{manifest_files}" ] && [ -s "{manifest_files}" ]; then
    while IFS= read -r manifest; do
        htar -rvf {archive_path} "$manifest"
    done < "{manifest_files}"
fi

# Verify archive
if ! htar -tvf {archive_path}; then
    echo "Archive verification failed"
    exit 1
fi

# Create temporary manifest entry
manifest_entry="{archive_path}:"
manifest_entry+=$(cat {chunk_files} | tr '\\n' ',' | sed 's/,$//')
echo $manifest_entry > chunk_{chunk_id}_manifest.txt

# Update manifest on tape
if ! hsi ls -l {self.archive_root}/archive_manifest.txt > /dev/null 2>&1; then
    # Create new manifest
    hsi put chunk_{chunk_id}_manifest.txt : {self.archive_root}/archive_manifest.txt
else
    # Append to existing manifest
    hsi get {self.archive_root}/archive_manifest.txt
    cat chunk_{chunk_id}_manifest.txt >> archive_manifest.txt
    hsi put archive_manifest.txt : {self.archive_root}/archive_manifest.txt
    rm archive_manifest.txt
fi

# Cleanup
# Note: we keep the file list and split files for potential reuse/verification
echo "Archive complete. File list saved as: {chunk_files}"
echo "Remove {chunk_files} and split files manually after verifying the archive"
rm chunk_{chunk_id}_manifest.txt manifest_files
"""

        script_path = f"archive_chunk_{chunk_id}.sh"
        with open(script_path, 'w') as f:
            f.write(script_content)

        return script_path

    def generate_documentation(self, chunks: List[List[str]], dir_sizes: Dict[str, int]) -> str:
        """
        Generate markdown documentation for the archive
        Returns the documentation content as a string
        """
        #timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        timestamp = datetime.datetime.now().strftime("%Y%m%d")
        doc = f"""# Data Archive Documentation

## Archive Overview
- Original Data Location: {self.root_dir}
- Archive Location: {self.archive_root}
- Total Chunks: {len(chunks)}
- Archive Date: {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
- Archive Mode: {'Active' if self.create_archive else 'Dry Run'}

## Directory Structure
Total directories found: {len(dir_sizes)}

### Largest Directories (Top 20)
| Directory | Size (TB) | % of Total |
|-----------|-----------|------------|
"""
        total_size = sum(dir_sizes.values())
        sorted_dirs = sorted(dir_sizes.items(), key=lambda x: x[1], reverse=True)
        for path, size in sorted_dirs[:20]:
            relative_path = str(Path(path).relative_to(self.root_dir))
            doc += f"| {relative_path} | {size / (1024**4):.2f} | {(size/total_size)*100:.1f}% |\n"

        doc += "\n## Archive Chunks\n"
        for i, chunk in enumerate(chunks, 1):
            total_chunk_size = sum(Path(f).stat().st_size for f in chunk)
            doc += f"\n### Chunk {i}\n"
            doc += f"- Archive Name: archive_chunk_{i}_{timestamp}.tar\n"
            doc += f"- Size: {total_chunk_size / (1024**4):.2f} TB\n"
            doc += f"- Files: {len(chunk)}\n"

            # Group files by directory for better organization
            files_by_dir = {}
            for f in chunk:
                dir_path = str(Path(f).parent.relative_to(self.root_dir))
                if dir_path not in files_by_dir:
                    files_by_dir[dir_path] = []
                files_by_dir[dir_path].append(Path(f).name)

            doc += "- Content Summary:\n"
            for dir_path, files in sorted(files_by_dir.items()):
                doc += f"  - {dir_path}/\n"
                for f in sorted(files)[:5]:  # Show first 5 files per directory
                    doc += f"    - {f}\n"
                if len(files) > 5:
                    doc += f"    - ... ({len(files)-5} more files)\n"

        doc += """
## Retrieval Instructions

### Finding Your Files
1. Search the manifest file for your file:
   ```bash
   grep "path/to/your/file" archive_manifest.txt
   ```

2. Or use the provided search script:
   ```bash
   ./search_archive.py "filename_pattern"
   ```

### Retrieving Files
1. From a known archive:
   ```bash
   htar -xvf /path/to/archive.tar path/to/desired/file
   ```

2. Extracting entire chunks:
   ```bash
   htar -xvf /path/to/archive.tar
   ```

3. Interactive browsing:
   ```bash
   htar -tvf /path/to/archive.tar | less
   ```

## Important Notes
- Archives are stored on the NERSC tape system
- Retrieval times may vary depending on tape availability
- All sizes are in binary units (1 GB = 1024^3 bytes)
"""
        return doc, timestamp
    def generate_wiki_documentation(self, chunks: List[List[str]], dir_sizes: Dict[str, int]) -> str:
        """
        Generate track wiki format documentation for the archive
        Returns the documentation content as a string
        """
        timestamp = datetime.datetime.now().strftime("%Y%m%d")
        doc = f"""= Data Archive Documentation =

== Archive Overview ==
 * Original Data Location: {self.root_dir}
 * Archive Location: {self.archive_root}
 * Total Chunks: {len(chunks)}
 * Archive Date: {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
 * Archive Mode: {'Active' if self.create_archive else 'Dry Run'}

== Directory Structure ==
Total directories found: {len(dir_sizes)}

=== Largest Directories (Top 20) ===
"""
        # Track Wiki table format
        doc += "|| Directory || Size (TB) || % of Total ||\n"

        total_size = sum(dir_sizes.values())
        sorted_dirs = sorted(dir_sizes.items(), key=lambda x: x[1], reverse=True)
        for path, size in sorted_dirs[:20]:
            relative_path = str(Path(path).relative_to(self.root_dir))
            doc += f"|| {relative_path} || {size / (1024**4):.2f} || {(size/total_size)*100:.1f}% ||\n"

        doc += "\n== Archive Chunks ==\n"
        for i, chunk in enumerate(chunks, 1):
            total_chunk_size = sum(Path(f).stat().st_size for f in chunk)
            doc += f"\n=== Chunk {i} ===\n"
            doc += f" * Archive Name: archive_chunk_{i}_{timestamp}.tar\n"
            doc += f" * Size: {total_chunk_size / (1024**4):.2f} TB\n"
            doc += f" * Files: {len(chunk)}\n"

            # Group files by directory for better organization
            files_by_dir = {}
            for f in chunk:
                dir_path = str(Path(f).parent.relative_to(self.root_dir))
                if dir_path not in files_by_dir:
                    files_by_dir[dir_path] = []
                files_by_dir[dir_path].append(Path(f).name)

            doc += " * Content Summary:\n"
            for dir_path, files in sorted(files_by_dir.items()):
                doc += f"   * {dir_path}/\n"
                for f in sorted(files)[:5]:  # Show first 5 files per directory
                    doc += f"     * {f}\n"
                if len(files) > 5:
                    doc += f"     * ... ({len(files)-5} more files)\n"

        doc += """
== Retrieval Instructions ==
=== Finding Your Files ===
1. Search the manifest file for your file:
{{{
grep "path/to/your/file" archive_manifest.txt
}}}

2. Or use the provided search script:
{{{
./search_archive.py "filename_pattern"
}}}

=== Retrieving Files ===
1. From a known archive:
{{{
htar -xvf /path/to/archive.tar path/to/desired/file
}}}

2. Extracting entire chunks:
{{{
htar -xvf /path/to/archive.tar
}}}

3. Interactive browsing:
{{{
htar -tvf /path/to/archive.tar | less
}}}

== Archive Manifest ==
The complete mapping of files to archives is maintained in:
 * Main manifest: {self.archive_root}/archive_manifest.txt
 * This documentation: {self.archive_root}/docs/archive_{timestamp}.txt
 * Search index: {self.archive_root}/docs/file_index.json

== Important Notes ==
 * Archives are stored on the NERSC tape system
 * Retrieval times may vary depending on tape availability
 * All sizes are in binary units (1 TB = 1024⁴ bytes)
 * Check archive_documentation.txt for the most recent archive status
"""
        return doc, timestamp

    def create_search_script(self) -> str:
        """Create a script to search through the archives"""
        script_content = """#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path

def search_archives(pattern: str, index_file: str = 'file_index.json'):
    with open(index_file, 'r') as f:
        file_index = json.load(f)

    matches = []
    regex = re.compile(pattern)

    for file_path, archive_info in file_index.items():
        if regex.search(file_path):
            matches.append((file_path, archive_info))

    return matches
def main():
    parser = argparse.ArgumentParser(description='Search archived files')
    parser.add_argument('pattern', help='File pattern to search for')
    parser.add_argument('--index', default='file_index.json',
                       help='Path to file index (default: file_index.json)')
    
    args = parser.parse_args()
    
    matches = search_archives(args.pattern, args.index)
    
    if not matches:                                                                     
        print(f"No files found matching pattern: {args.pattern}")
        return
    
    print(f"Found {len(matches)} matching files:")
    for file_path, archive_info in matches:
        print(f"\\nFile: {file_path}")
        print(f"Archive: {archive_info['archive']}")
        print(f"Size: {archive_info['size']/1024**2:.2f} MB")
        print(f"Archived: {archive_info['date']}")

if __name__ == '__main__':
    main()
"""
        return script_content
    def create_file_index(self, chunks: List[List[str]], timestamp: str) -> Dict[str, Dict]:
        """Create a searchable index of all archived files"""
        index = {}
        for i, chunk in enumerate(chunks, 1):
            archive_name = f"archive_chunk_{i}_{timestamp}.tar"
            archive_path = str(self.archive_root / archive_name)
            
            for file_path in chunk:
                rel_path = str(Path(file_path).relative_to(self.root_dir))
                index[rel_path] = {
                    'archive': archive_path,
                    'size': Path(file_path).stat().st_size,
                    'date': timestamp,
                    'chunk': i
                }
        
        return index


    def write_documentation(self, doc_content: str, wikidoc_content: str, timestamp: str, chunks: List[List[str]]):
        """Write all documentation files"""
        # Create documentation directory
        #if not self.tape_ops.check_path_exists(doc_dir):
        #    if not self.tape_ops.create_directory(doc_dir):
        #        raise HSIException(f"Failed to create archive directory: {doc_dir}")

        # Write main documentation
        doc_path = self.doc_dir / f"archive_{timestamp}.md"
        with open(doc_path, 'w') as f:
            f.write(doc_content)

        # Write main documentation
        #wikidoc_path =self.doc_dir / f"archive_{timestamp}.wiki"
        #with open(wikidoc_path, 'w') as f:
        #    f.write(wikidoc_content)

        # Create a symlink to latest documentation
        latest_link = self.doc_dir / "latest.md"
        if latest_link.exists():
            latest_link.unlink()
        latest_link.symlink_to(doc_path.name)

        # Create file index
        index = self.create_file_index(chunks, timestamp)
        index_path = self.doc_dir / "file_index.json"
        with open(index_path, 'w') as f:
            json.dump(index, f, indent=2)

        # Create search script
        #search_script = self.doc_dir / "search_archive.py"
        #with open(search_script, 'w') as f:
        #    f.write(self.create_search_script())
        #search_script.chmod(0o755)  # Make executable

        return doc_path



    def run(self):
        """Main execution method"""
        logging.info(f"Starting archive process for {self.root_dir}")
        logging.info(f"Mode: {'Archive' if self.create_archive else 'Dry run'}")

        try:
            # Check existing archives first
            existing_archives = self.check_existing_archives()
            if existing_archives:
                logging.info(f"Found {len(existing_archives)} files already archived")

            # Get directory sizes
            dir_sizes = self.get_directory_sizes()
            logging.info(f"Completed initial directory scan")

            # Scan files in parallel
            file_sizes = self.parallel_scan_large_directory()
            logging.info(f"Found {len(file_sizes)} files to process")

            # Remove already archived files
            new_files = {
                path: size for path, size in file_sizes.items()
                if path not in existing_archives
            }

            if len(new_files) != len(file_sizes):
                logging.info(f"Skipping {len(file_sizes) - len(new_files)} already archived files")

            if not new_files:
                logging.info("No new files to archive")
                return

            # Group remaining files into chunks
            chunks = self.group_files_into_chunks(new_files)
            logging.info(f"Created {len(chunks)} chunks for new files")

            # Create Slurm scripts
            slurm_scripts = []
            for i, chunk in enumerate(chunks, 1):
                script_path = self.create_slurm_script(i, chunk)
                slurm_scripts.append(script_path)
                logging.info(f"Created Slurm script and file list: {script_path}")

            # Generate documentation and write all files
            doc_content, timestamp = self.generate_documentation(chunks, dir_sizes)
            wikidoc_content, timestamp = self.generate_wiki_documentation(chunks, dir_sizes)
            doc_path = self.write_documentation(doc_content, wikidoc_content, timestamp, chunks)
            logging.info(f"Generated documentation: {doc_path}")


            # Create a nested archive directory
            success = self.tape_ops.create_archive_directory(self.archive_root_str)
            if success:
                print("Archive directory structure created successfully")
            else:
                print("Failed to create archive directory structure")

            # Submit Slurm jobs if create_archive is True
            if self.create_archive:
                for script in slurm_scripts:
                    try:
                        result = subprocess.run(['sbatch', script],
                                         check=True,
                                         capture_output=True,
                                         text=True)
                        job_id = result.stdout.strip().split()[-1]
                        logging.info(f"Submitted job {job_id}: {script}")
                    except subprocess.CalledProcessError as e:
                        logging.error(f"Failed to submit job {script}: {e.stderr}")
            else:
                logging.info("Dry run complete. No jobs submitted.")
                logging.info(f"To submit jobs, run again with --create-archive")

                # Print summary
                print("\nDry Run Summary:")
                print(f"Total files found: {len(file_sizes)}")
                print(f"Already archived: {len(existing_archives)}")
                print(f"New files to archive: {len(new_files)}")
                print(f"Number of chunks: {len(chunks)}")
                print(f"Generated scripts: {len(slurm_scripts)}")
        except Exception as e:
            logging.error(f"Error during archive process: {e}")
            raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Archive large datasets at NERSC")
    parser.add_argument("root_dir", help="Root directory containing data to archive")
    parser.add_argument("archive_root", help="Target directory on tape system")
    parser.add_argument("--chunk-size", type=int, default=20480,
                       help="Maximum size of each archive chunk in GB (default: 20480 GB = 20 TB)")
    parser.add_argument("--num-workers", type=int, default=8,
                       help="Number of parallel workers for directory scanning")
    parser.add_argument("--create-archive", action="store_true",
                       help="If set, submit archive jobs; otherwise, perform dry run only")
    args = parser.parse_args()

    archiver = DataArchiver(
        args.root_dir,
        args.archive_root,
        args.chunk_size,
        args.create_archive
    )
    archiver.run()

    # Finally we would also like to tar the docs directory
    comm=f'htar -cvf {archiver.archive_root}/docs.tar {archiver.root_dir}/docs'
    result = subprocess.run(comm, shell=True, check=False,
                                  capture_output=True, text=True) 
    print(comm)
    print(result.stdout)
    print(result.stderr)
