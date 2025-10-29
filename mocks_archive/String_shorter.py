import hashlib
import base64
import re

def string_to_short_code(input_string, max_length=32, preserve_extension=True):
    """
    Convert a long string (like a filepath) to a shorter code while trying to maintain uniqueness.
    
    Args:
        input_string (str): The input string to be shortened
        max_length (int): Maximum desired length of the output code (default: 32)
        preserve_extension (bool): Whether to preserve the file extension if present (default: True)
    
    Returns:
        str: A shortened version of the input string
    """
    # Handle empty input
    if not input_string:
        return ""
    
    # Extract extension if needed
    extension = ""
    if preserve_extension and '.' in input_string:
        extension = '.' + input_string.split('.')[-1]
        # Adjust max_length to account for extension
        max_length = max(max_length - len(extension), 8)
    
    # Create SHA-256 hash of input string
    hash_obj = hashlib.sha256(input_string.encode('utf-8'))
    hash_digest = hash_obj.digest()
    
    # Convert to base64 to get a shorter string
    b64_string = base64.urlsafe_b64encode(hash_digest).decode('utf-8')
    
    # Remove base64 padding characters
    b64_string = b64_string.rstrip('=')
    
    # Keep only alphanumeric characters
    clean_string = re.sub(r'[^a-zA-Z0-9]', '', b64_string)
    
    # Truncate to desired length
    shortened = clean_string[:max_length]
    
    # Add back extension if it was preserved
    if extension:
        shortened += extension
    
    return shortened

def create_path_shortener(max_segment_length=32):
    """
    Creates a function that shortens entire paths while preserving structure.
    
    Args:
        max_segment_length (int): Maximum length for each path segment
    
    Returns:
        function: A function that shortens paths
    """
    def shorten_path(filepath):
        parts = filepath.split('/')
        shortened_parts = []
        
        for i, part in enumerate(parts):
            # Don't shorten empty parts (occurs with leading/trailing slashes)
            if not part:
                shortened_parts.append(part)
                continue
                
            # Only shorten if longer than max_segment_length
            if len(part) > max_segment_length:
                # Preserve extension only for the last part
                preserve_ext = (i == len(parts) - 1)
                shortened = string_to_short_code(part, max_segment_length, preserve_ext)
                shortened_parts.append(shortened)
            else:
                shortened_parts.append(part)
        
        return '/'.join(shortened_parts)
    
    return shorten_path

# Additional utility functions for checking collisions
def check_collision_probability(strings, max_length=32):
    """
    Estimate collision probability for a set of strings using the shortening function.
    
    Args:
        strings (list): List of strings to test
        max_length (int): Maximum length to use for shortening
    
    Returns:
        tuple: (collision_count, collision_pairs)
    """
    shortened_dict = {}
    collisions = []
    
    for s in strings:
        short = string_to_short_code(s, max_length)
        if short in shortened_dict:
            collisions.append((s, shortened_dict[short]))
        shortened_dict[short] = s
    
    return len(collisions), collisions
