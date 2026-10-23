# File: 3_verification_resources/sdram.py
# Description: Packs grayscale pixels into 16-bit words and unpacks them.

# This helper uses row-major pixels with the low byte first.
# The packing does not verify the SDRAM controller or board interface.
from __future__ import annotations
import zlib


# Function: pack_u16_low_byte_first
# Description: Packs pairs of 8-bit pixels into 16-bit words.
def pack_u16_low_byte_first(pixels):
    if len(pixels)!=450*450 or any(not 0<=p<=255 for p in pixels):
        raise ValueError('expected 450x450 unsigned grayscale frame')
    return [pixels[i] | (pixels[i+1]<<8) for i in range(0,len(pixels),2)]


# Function: unpack_u16_low_byte_first
# Description: Extracts two grayscale pixels from each 16-bit word.
def unpack_u16_low_byte_first(words):
    if len(words)!=450*450//2 or any(not 0<=word<=65535 for word in words):
        raise ValueError('invalid SDRAM word data')
    return [byte for word in words for byte in (word&255,word>>8)]


# Function: image_crc32
# Description: Calculates the CRC32 checksum of the pixel bytes.
def image_crc32(pixels):
    return f'{zlib.crc32(bytes(pixels)) & 0xffffffff:08X}'
