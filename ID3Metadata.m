// ID3Metadata.m — ID3 tag parser with encoding detection
// Supports ID3v1, ID3v2.3, ID3v2.4
// Detects: UTF-8, UTF-16 LE/BE, Windows-1251, ISO-8859-1
// Mojibake recovery for common UTF-8 ↔ Windows-1251 mismatches

#import "ID3Metadata.h"
#import <AVFoundation/AVFoundation.h>
#import <Cocoa/Cocoa.h>

// ──────────────────────────────────────────────
// Debug logging
// ──────────────────────────────────────────────
static BOOL gDebugMode = NO;

#define DLog(fmt, ...) \
    if (gDebugMode) { \
        NSLog(@"[ID3] " fmt, ##__VA_ARGS__); \
    }

// ──────────────────────────────────────────────
// Encoding detection helpers
// ──────────────────────────────────────────────
typedef struct {
    NSStringEncoding encoding;
    NSString *name;
    float score;
} EncodingResult;

/// Score a decoded string for text quality (higher = better)
static float ScoreText(NSString *text) {
    if ([text length] == 0) return 0;
    NSUInteger len = [text length];
    float total = 0;
    NSUInteger replacementCount = 0;
    NSUInteger cyrillicCount = 0;
    NSUInteger printableCount = 0;

    for (NSUInteger i = 0; i < len; i++) {
        unichar c = [text characterAtIndex:i];

        if (c == 0xFFFD) {
            total -= 15;
            replacementCount++;
        } else if (c >= 0x20 && c < 0x7F) {
            total += 1.5;  // printable ASCII
            printableCount++;
        } else if (c >= 0x0400 && c <= 0x04FF) {
            total += 5.0;  // Cyrillic bonus
            cyrillicCount++;
        } else if (c >= 0x0080 && c < 0x0100) {
            total += 0.5;  // Latin-1 supplement
            printableCount++;
        } else if (c == 0x0A || c == 0x0D || c == 0x09) {
            total += 0.1;  // whitespace
        } else if (c >= 0x2000 && c < 0x20FF) {
            total += 0.5;  // punctuation
        } else if (c >= 0x3000 && c < 0x9FFF) {
            total += 2.0;  // CJK
        } else if (c >= 0xE000 && c < 0xF900) {
            total -= 2.0;  // Private Use Area (usually garbage)
        } else if (c < 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) {
            total -= 10;   // non-printable control chars
        } else if (c > 0x7E && c < 0xA0) {
            total -= 3.0;  // C1 control chars
        } else if (c >= 0x0100 && c < 0x0400) {
            total += 1.0;  // Latin Extended, Greek etc
        } else {
            total += 0.5;
        }
    }

    // Strong bonus for no replacement characters at all
    if (replacementCount == 0) total += len * 2;

    // Bonus for Cyrillic content (it's a primary target)
    if (cyrillicCount > 0) total += cyrillicCount * 2;

    // Penalty for too few printable characters
    float printableRatio = (float)printableCount / (float)len;
    if (printableRatio < 0.5) total -= len * 3;

    return total / (float)len;  // normalize
}

/// Detect whether raw bytes look like they contain null bytes (UTF-16 hint)
static BOOL HasNullBytes(const unsigned char *bytes, NSUInteger length) {
    if (length < 4) return NO;
    // Check for null bytes with regular spacing (UTF-16 pattern)
    // or leading BOM nulls
    for (NSUInteger i = 0; i < length - 1; i++) {
        if (bytes[i] == 0x00 && (bytes[i+1] >= 0x20 && bytes[i+1] < 0x7F)) {
            return YES;
        }
        if (bytes[i] >= 0x20 && bytes[i+1] == 0x00) {
            return YES;
        }
    }
    return bytes[0] == 0xFF && bytes[1] == 0xFE;  // UTF-16 LE BOM first null
}

/// Detect mojibake: UTF-8 Cyrillic bytes misread as Latin-1 / Windows-1251
/// When bytes 0xD0-0xD4 (UTF-8 Cyrillic leads) are interpreted as Latin-1 they
/// become Ð (U+00D0) through Ô (U+00D4). Continuation bytes 0x80-0xBF become control
/// chars or punctuation. Scan for this pattern without NSRegularExpression to avoid
/// regex engine crashes from invalid character ranges.
static BOOL IsLikelyMojibake(NSString *text) {
    NSUInteger len = [text length];
    if (len < 2) return NO;
    NSUInteger matchCount = 0;
    for (NSUInteger i = 0; i < len - 1; i++) {
        unichar c1 = [text characterAtIndex:i];
        unichar c2 = [text characterAtIndex:i + 1];
        // Lead byte range: Ð (0xD0) through Ô (0xD4)
        BOOL isLead = (c1 >= 0xD0 && c1 <= 0xD4);
        // Continuation byte range in Latin-1: 0x80-0xBF → Unicode U+0080-U+00BF
        // This includes control chars, punctuation, and some Latin chars
        BOOL isCont = (c2 >= 0x80 && c2 <= 0xBF);
        if (isLead && isCont) matchCount++;
    }
    return (matchCount > 0 && (float)matchCount / (float)len > 0.10);
}

/// Attempt to fix common UTF-8 ↔ Windows-1251 mojibake
static NSString *FixMojibake(NSString *text) {
    if (!IsLikelyMojibake(text)) return text;

    DLog(@"Mojibake detected in: '%@'", text);

    // Try: current string was decoded as Windows-1251, but should be UTF-8.
    // Re-encode as Windows-1251 to get original bytes, then decode as UTF-8.
    // Also try the reverse (UTF-8 decode of Windows-1251 byte stream).

    NSString *fixed = nil;

    // Attempt 1: String is Windows-1251 misinterpretation → re-encode as 1251, decode as UTF-8
    NSData *raw1251 = [text dataUsingEncoding:NSWindowsCP1251StringEncoding allowLossyConversion:YES];
    if (raw1251) {
        fixed = [[[NSString alloc] initWithData:raw1251 encoding:NSUTF8StringEncoding] autorelease];
        if (fixed && ScoreText(fixed) > ScoreText(text) * 1.5) {
            DLog(@"Mojibake fixed via Windows-1251→UTF-8: '%@' -> '%@'", text, fixed);
            return fixed;
        }
    }

    // Attempt 2: String is ISO-8859-1 misinterpretation → re-encode as ISO Latin 1, decode as UTF-8
    NSData *rawLatin1 = [text dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES];
    if (rawLatin1) {
        fixed = [[[NSString alloc] initWithData:rawLatin1 encoding:NSUTF8StringEncoding] autorelease];
        if (fixed && ScoreText(fixed) > ScoreText(text) * 1.5) {
            DLog(@"Mojibake fixed via ISO-8859-1→UTF-8: '%@' -> '%@'", text, fixed);
            return fixed;
        }
    }

    // Attempt 3: String was double-encoded UTF-8
    NSData *rawUTF8 = [text dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    if (rawUTF8) {
        NSString *doubleDecoded = [[[NSString alloc] initWithData:rawUTF8 encoding:NSUTF8StringEncoding] autorelease];
        if (doubleDecoded && ScoreText(doubleDecoded) > ScoreText(text) * 1.5) {
            DLog(@"Mojibake fixed via double UTF-8 decode: '%@' -> '%@'", text, doubleDecoded);
            return doubleDecoded;
        }
    }

    return text;  // couldn't fix, return original
}

/// Try all encodings and return the best one
static NSString *DecodeWithBestEncoding(NSData *data, NSString **outDetectedEncoding) {
    if (!data || [data length] == 0) {
        if (outDetectedEncoding) *outDetectedEncoding = @"none";
        return @"";
    }

    const unsigned char *bytes = (const unsigned char *)[data bytes];
    NSUInteger length = [data length];

    // Try UTF-16 first if BOM or null bytes present
    if (HasNullBytes(bytes, length)) {
        // UTF-16 LE with BOM
        if (length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
            NSString *s = [[[NSString alloc] initWithData:data encoding:NSUTF16LittleEndianStringEncoding] autorelease];
            if (s) {
                float score = ScoreText(s);
                DLog(@"UTF-16 LE (BOM): score=%.2f '%@'", score, [s substringToIndex:MIN(30, [s length])]);
                if (score > -1) {
                    if (outDetectedEncoding) *outDetectedEncoding = @"UTF-16 LE";
                    return s;
                }
            }
        }
        // UTF-16 BE with BOM
        if (length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
            NSString *s = [[[NSString alloc] initWithData:data encoding:NSUTF16BigEndianStringEncoding] autorelease];
            if (s) {
                float score = ScoreText(s);
                DLog(@"UTF-16 BE (BOM): score=%.2f '%@'", score, [s substringToIndex:MIN(30, [s length])]);
                if (score > -1) {
                    if (outDetectedEncoding) *outDetectedEncoding = @"UTF-16 BE";
                    return s;
                }
            }
        }
        // Try UTF-16 LE without BOM (assume LE if null bytes)
        NSString *s = [[[NSString alloc] initWithData:data encoding:NSUTF16LittleEndianStringEncoding] autorelease];
        if (s && ScoreText(s) > 0) {
            float score = ScoreText(s);
            DLog(@"UTF-16 LE (detected): score=%.2f '%@'", score, [s substringToIndex:MIN(30, [s length])]);
            if (score > -1) {
                if (outDetectedEncoding) *outDetectedEncoding = @"UTF-16 LE";
                return s;
            }
        }
    }

    // Try UTF-8
    NSString *utf8Result = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (utf8Result) {
        float score = ScoreText(utf8Result);
        DLog(@"UTF-8: score=%.2f '%@'", score, [utf8Result substringToIndex:MIN(30, [utf8Result length])]);
        // Check for mojibake even in UTF-8
        if (IsLikelyMojibake(utf8Result)) {
            NSString *fixed = FixMojibake(utf8Result);
            if (fixed != utf8Result) {
                DLog(@"UTF-8 result was mojibake, fixed to: '%@'", fixed);
                if (outDetectedEncoding) *outDetectedEncoding = @"UTF-8 (mojibake-fixed via Windows-1251)";
                return fixed;
            }
        }
        if (score > 0.5) {
            if (outDetectedEncoding) *outDetectedEncoding = @"UTF-8";
            return utf8Result;
        }
        // UTF-8 decodes but scores poorly — keep as candidate
    }

    // Try Windows-1251 (Cyrillic)
    NSString *win1251Result = [[[NSString alloc] initWithData:data encoding:NSWindowsCP1251StringEncoding] autorelease];
    float win1251Score = win1251Result ? ScoreText(win1251Result) : -999;

    // Try ISO-8859-1 (Latin-1)
    NSString *latin1Result = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    float latin1Score = latin1Result ? ScoreText(latin1Result) : -999;

    DLog(@"Windows-1251: score=%.2f ISO-8859-1: score=%.2f",
          win1251Score, latin1Score);

    // If we had a low-scoring UTF-8, compare
    float utf8Score = utf8Result ? ScoreText(utf8Result) : -999;

    // Pick the best
    float bestScore = utf8Score;
    NSString *bestResult = utf8Result;
    NSString *bestEncoding = @"UTF-8";

    if (win1251Score > bestScore) {
        bestScore = win1251Score;
        bestResult = win1251Result;
        bestEncoding = @"Windows-1251";
    }
    if (latin1Score > bestScore) {
        bestScore = latin1Score;
        bestResult = latin1Result;
        bestEncoding = @"ISO-8859-1";
    }

    DLog(@"Best: %@ (score=%.2f)", bestEncoding, bestScore);

    if (outDetectedEncoding) *outDetectedEncoding = bestEncoding;

    // Apply mojibake fix to best result
    if (bestResult) {
        NSString *fixed = FixMojibake(bestResult);
        if (fixed != bestResult) {
            if (outDetectedEncoding) *outDetectedEncoding = [bestEncoding stringByAppendingString:@" (mojibake-fixed)"];
        }
        return fixed;
    }

    // Last resort: Latin-1 always succeeds (it maps all bytes), use it
    if (latin1Result) {
        if (outDetectedEncoding) *outDetectedEncoding = @"ISO-8859-1 (fallback)";
        return latin1Result;
    }

    if (outDetectedEncoding) *outDetectedEncoding = @"unknown";
    return @"";
}

// ──────────────────────────────────────────────
// ID3v1 parser (128 bytes at end of file)
// ──────────────────────────────────────────────
static ID3MetadataResult *ParseID3v1(NSData *fileData) {
    NSUInteger fileLen = [fileData length];
    if (fileLen < 128) return nil;

    const unsigned char *bytes = (const unsigned char *)[fileData bytes];
    NSUInteger offset = fileLen - 128;

    // Check "TAG" magic
    if (bytes[offset] != 'T' || bytes[offset+1] != 'A' || bytes[offset+2] != 'G') {
        return nil;
    }

    DLog(@"ID3v1 tag found at offset %lu", (unsigned long)offset);

    ID3MetadataResult *result = [[[ID3MetadataResult alloc] init] autorelease];

    // Helper: read a fixed-length field, strip trailing whitespace/null
    NSString *(^readField)(NSUInteger, NSUInteger) = ^NSString *(NSUInteger start, NSUInteger len) {
        // Find actual end (strip nulls and spaces)
        NSUInteger end = start + len;
        while (end > start && (bytes[end-1] == 0 || bytes[end-1] == ' ')) {
            end--;
        }
        if (end == start) return @"";
        NSData *fieldData = [NSData dataWithBytes:bytes + start length:(end - start)];
        // ID3v1 is always single-byte — use auto-detection (handles Windows-1251, Latin-1)
        NSString *detectedEnc = nil;
        NSString *str = DecodeWithBestEncoding(fieldData, &detectedEnc);
        DLog(@"ID3v1 field: detected=%@ '%@'", detectedEnc, [str substringToIndex:MIN(20, [str length])]);
        return str;
    };

    result.title = readField(offset + 3, 30);
    result.artist = readField(offset + 33, 30);
    result.album = readField(offset + 63, 30);
    // Skip Year (offset+93, 4 bytes)
    // Skip Comment (offset+97, 30 bytes)
    // Skip Genre (offset+127, 1 byte)

    DLog(@"ID3v1: title='%@' artist='%@' album='%@'", result.title, result.artist, result.album);

    // Only return if at least one field has content
    if ([result.title length] > 0 || [result.artist length] > 0 || [result.album length] > 0) {
        return result;
    }
    return nil;
}

// ──────────────────────────────────────────────
// ID3v2 parser (variable frames at start of file)
// ──────────────────────────────────────────────
/// Read a syncsafe integer (ID3v2 size encoding: 7 bits per byte, MSB always 0)
static uint32_t ReadSyncsafeInt(const unsigned char *bytes) {
    return ((uint32_t)bytes[0] << 21) |
           ((uint32_t)bytes[1] << 14) |
           ((uint32_t)bytes[2] << 7)  |
           ((uint32_t)bytes[3]);
}

static ID3MetadataResult *ParseID3v2(NSData *fileData) {
    NSUInteger fileLen = [fileData length];
    if (fileLen < 10) return nil;

    const unsigned char *bytes = (const unsigned char *)[fileData bytes];

    // Check "ID3" magic
    if (bytes[0] != 'I' || bytes[1] != 'D' || bytes[2] != '3') {
        return nil;
    }

    uint8_t majorVersion = bytes[3];
    // uint8_t minorVersion = bytes[4];
    uint8_t flags = bytes[5];
    uint32_t tagSize = ReadSyncsafeInt(bytes + 6);

    DLog(@"ID3v2.%d tag found, size=%u, flags=0x%02x", majorVersion, tagSize, flags);

    // Sanity check tag size
    if (tagSize > fileLen - 10 || tagSize > 10 * 1024 * 1024) { // max 10MB sanity
        DLog(@"ID3v2 tag size suspicious (%u), skipping", tagSize);
        return nil;
    }

    NSUInteger pos = 10;  // start of frames (after header)

    // ID3v2.4 extended header?
    if (majorVersion == 4 && (flags & 0x40)) {
        if (pos + 4 > fileLen) return nil;
        uint32_t extSize = ReadSyncsafeInt(bytes + pos);
        pos += 4 + extSize;  // skip extended header
    }
    // ID3v2.3 extended header?
    if (majorVersion == 3 && (flags & 0x40)) {
        if (pos + 4 > fileLen) return nil;
        uint32_t extSize = ((uint32_t)bytes[pos] << 24) |
                           ((uint32_t)bytes[pos+1] << 16) |
                           ((uint32_t)bytes[pos+2] << 8) |
                           ((uint32_t)bytes[pos+3]);
        pos += 4 + extSize;  // skip extended header
    }

    // Footer present? (ID3v2.4, flag 0x10)
    // If footer is present, tagSize includes it, but frame data ends 10 bytes before footer
    NSUInteger frameEnd = pos + tagSize;
    if (majorVersion == 4 && (flags & 0x10)) {
        frameEnd -= 10;  // exclude footer from frame search
    }

    // Frame IDs we care about
    NSDictionary *frameMap = @{
        @"TIT2": @"title",
        @"TPE1": @"artist",
        @"TPE2": @"albumArtist",
        @"TALB": @"album",
        @"TCON": @"genre",
    };

    ID3MetadataResult *result = [[[ID3MetadataResult alloc] init] autorelease];
    __block BOOL hasAnyField = NO;

    // Cached encoding per URL — we store in static NSMutableDictionary
    static NSMutableDictionary *encodingCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        encodingCache = [[NSMutableDictionary alloc] init];
    });

    while (pos + 8 <= frameEnd && pos + 8 <= fileLen) {
        char frameID[5] = {0};
        memcpy(frameID, bytes + pos, 4);
        uint32_t frameSize;
        uint16_t frameFlags __unused = 0;

        if (majorVersion == 4) {
            // ID3v2.4: frame size is syncsafe integer (7 bits per byte)
            if (pos + 10 > fileLen) break;
            frameSize = ReadSyncsafeInt(bytes + pos + 4);
            frameFlags = (uint16_t)bytes[pos + 8] << 8 | (uint16_t)bytes[pos + 9];
            pos += 10;
        } else {
            // ID3v2.2 or 2.3: frame size is regular 4-byte integer
            if (pos + 10 > fileLen) break;
            frameSize = ((uint32_t)bytes[pos + 4] << 24) |
                        ((uint32_t)bytes[pos + 5] << 16) |
                        ((uint32_t)bytes[pos + 6] << 8)  |
                        ((uint32_t)bytes[pos + 7]);
            frameFlags = (uint16_t)bytes[pos + 8] << 8 | (uint16_t)bytes[pos + 9];
            pos += 10;
        }

        if (frameSize == 0) break;  // padding reached
        if (pos + frameSize > fileLen) break;

        NSString *frameIDStr = [NSString stringWithUTF8String:frameID];
        NSString *fieldKey = frameMap[frameIDStr];

        if (fieldKey && frameSize > 1) {
            // Read encoding byte (first byte of frame data)
            uint8_t encodingByte = bytes[pos];
            NSUInteger dataStart = pos + 1;
            NSUInteger dataLen = frameSize - 1;

            if (dataLen > 0 && dataStart + dataLen <= fileLen) {
                NSData *frameData = [NSData dataWithBytes:bytes + dataStart length:dataLen];

                // Determine encoding from the encoding byte
                NSStringEncoding stringEncoding = 0;
                NSString *encName = @"unknown";

                switch (encodingByte) {
                    case 0: // ISO-8859-1
                        stringEncoding = NSISOLatin1StringEncoding;
                        encName = @"ISO-8859-1 (flag)";
                        break;
                    case 1: // UTF-16 with BOM
                    case 2: // UTF-16 BE (ID3v2.4)
                        stringEncoding = NSUTF16StringEncoding;  // respects BOM
                        encName = @"UTF-16 (flag)";
                        break;
                    case 3: // UTF-8 (ID3v2.4)
                        stringEncoding = NSUTF8StringEncoding;
                        encName = @"UTF-8 (flag)";
                        break;
                    default:
                        stringEncoding = 0;
                        break;
                }

                // The encoding flag byte is often wrong (many taggers set 0x00 = ISO-8859-1
                // but store Windows-1251 for Cyrillic). Always try ALL encodings and pick
                // the best-scoring result, using the flag only as a tiebreaker hint.
                NSString *detectedEnc = nil;
                NSString *decoded = DecodeWithBestEncoding(frameData, &detectedEnc);

                // If the flagged encoding (when non-Latin1) is different from the auto-detected
                // one AND scores well, prefer the flagged encoding as a tiebreaker.
                if (stringEncoding != 0 && stringEncoding != NSISOLatin1StringEncoding) {
                    NSString *flaggedDecoded = [[[NSString alloc] initWithData:frameData encoding:stringEncoding] autorelease];
                    if (flaggedDecoded) {
                        float flaggedScore = ScoreText(flaggedDecoded);
                        float autoScore = ScoreText(decoded);
                        if (flaggedScore > autoScore + 1.0) {
                            DLog(@"%@: flagged %@ (%.2f) beats auto-detect (%.2f), using flagged",
                                  fieldKey, encName, flaggedScore, autoScore);
                            decoded = flaggedDecoded;
                            detectedEnc = encName;
                        }
                    }
                }

                // Final mojibake check on whatever we chose
                if (decoded && IsLikelyMojibake(decoded)) {
                    NSString *fixed = FixMojibake(decoded);
                    if (fixed != decoded) {
                        DLog(@"  → mojibake fixed: '%@' -> '%@'", decoded, fixed);
                        decoded = fixed;
                        detectedEnc = [detectedEnc ?: @"" stringByAppendingString:@" (mojibake-fixed)"];
                    }
                }

                if (decoded && [decoded length] > 0) {
                    // Remove null-byte padding that sometimes appears in UTF-16
                    decoded = [decoded stringByTrimmingCharactersInSet:
                               [NSCharacterSet characterSetWithCharactersInString:@"\x00"]];

                    // Store field
                    if ([fieldKey isEqualToString:@"title"]) {
                        result.title = decoded;
                        hasAnyField = YES;
                    } else if ([fieldKey isEqualToString:@"artist"]) {
                        result.artist = decoded;
                        hasAnyField = YES;
                    } else if ([fieldKey isEqualToString:@"albumArtist"]) {
                        result.albumArtist = decoded;
                        hasAnyField = YES;
                    } else if ([fieldKey isEqualToString:@"album"]) {
                        result.album = decoded;
                        hasAnyField = YES;
                    } else if ([fieldKey isEqualToString:@"genre"]) {
                        result.genre = decoded;
                    }

                    // Cache detection info if debug
                    if (gDebugMode && detectedEnc) {
                        NSString *cacheKey = [NSString stringWithFormat:@"%@.%@", [frameIDStr substringToIndex:MIN(4, [frameIDStr length])], fieldKey];
                        encodingCache[cacheKey] = detectedEnc;
                    }
                }
            }
        }

        pos += frameSize;
    }

    return hasAnyField ? result : nil;
}

// ──────────────────────────────────────────────
// ID3Parser implementation
// ──────────────────────────────────────────────
static NSCache *_id3Cache = nil;

@implementation ID3MetadataResult
- (void)dealloc {
    [_title release];
    [_artist release];
    [_album release];
    [_albumArtist release];
    [_genre release];
    [super dealloc];
}
@end

@implementation ID3Parser

+ (void)initialize {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _id3Cache = [[NSCache alloc] init];
        [_id3Cache setCountLimit:500];
    });
}

+ (void)setDebugMode:(BOOL)enabled {
    gDebugMode = enabled;
}

+ (void)clearCache {
    [_id3Cache removeAllObjects];
}

+ (NSString *)detectedEncodingForURL:(NSURL *)url field:(NSString *)field {
    return nil;  // simplified: we don't store per-file in this version
}

+ (ID3MetadataResult *)parseMetadataFromURL:(NSURL *)url {
    // Check cache
    NSString *cacheKey = [url absoluteString];
    ID3MetadataResult *cached = [_id3Cache objectForKey:cacheKey];
    if (cached) return cached;

    // Read file data
    NSError *error = nil;
    NSData *fileData = [NSData dataWithContentsOfURL:url
                                             options:NSDataReadingMappedAlways
                                               error:&error];
    if (error || !fileData || [fileData length] == 0) {
        DLog(@"Failed to read file: %@", error);
        // Fallback to AVURLAsset for duration at least
        return [self fallbackToAVAsset:url];
    }

    ID3MetadataResult *result = nil;

    // Try ID3v2 first (more detailed and at the beginning of file)
    result = ParseID3v2(fileData);
    if (result) {
        DLog(@"ID3v2 parsing succeeded for %@", [url lastPathComponent]);
    }

    // Try ID3v1 as fallback (or to fill in missing fields)
    if (!result) {
        result = ParseID3v1(fileData);
        if (result) {
            DLog(@"ID3v1 parsing succeeded for %@", [url lastPathComponent]);
        }
    } else {
        // ID3v2 succeeded but may be missing fields that ID3v1 has
        ID3MetadataResult *v1 = ParseID3v1(fileData);
        if (v1) {
            if (!result.title && v1.title) result.title = v1.title;
            if (!result.artist && v1.artist) result.artist = v1.artist;
            if (!result.album && v1.album) result.album = v1.album;
        }
    }

    // If no ID3 tags found, fall back to AVURLAsset
    if (!result || ([result.title length] == 0 && [result.artist length] == 0)) {
        DLog(@"No ID3 tags found, falling back to AVURLAsset");
        ID3MetadataResult *avResult = [self fallbackToAVAsset:url];
        if (result) {
            // Merge: prefer ID3 data, fill with AVAsset
            if (!result.title && avResult.title) result.title = avResult.title;
            if (!result.artist && avResult.artist) result.artist = avResult.artist;
            if (!result.album && avResult.album) result.album = avResult.album;
            if (!result.albumArtist && avResult.albumArtist) result.albumArtist = avResult.albumArtist;
            result.duration = avResult.duration;
        } else {
            result = avResult;
        }
    }

    // Get duration from AVAsset
    if (result) {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
        result.duration = CMTimeGetSeconds([asset duration]);
    }

    // Apply mojibake fixing to all fields one more time
    if (result) {
        if (IsLikelyMojibake(result.title)) result.title = FixMojibake(result.title);
        if (IsLikelyMojibake(result.artist)) result.artist = FixMojibake(result.artist);
        if (IsLikelyMojibake(result.album)) result.album = FixMojibake(result.album);
        if (IsLikelyMojibake(result.albumArtist)) result.albumArtist = FixMojibake(result.albumArtist);
    }

    // Cache
    if (result) {
        [_id3Cache setObject:result forKey:cacheKey];
    }

    return result;
}

+ (ID3MetadataResult *)parseID3v2FromData:(NSData *)fileData {
    return ParseID3v2(fileData);
}

+ (ID3MetadataResult *)parseID3v1FromData:(NSData *)fileData {
    return ParseID3v1(fileData);
}

// ── Fallback to AVURLAsset ──
+ (ID3MetadataResult *)fallbackToAVAsset:(NSURL *)url {
    ID3MetadataResult *result = [[[ID3MetadataResult alloc] init] autorelease];
    result.title = [[url lastPathComponent] stringByDeletingPathExtension];
    result.artist = @"Unknown Artist";

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    result.duration = CMTimeGetSeconds([asset duration]);

    for (AVMetadataItem *item in [asset commonMetadata]) {
        NSString *key = [item commonKey];
        id value = [item value];
        if (!value || ![value isKindOfClass:[NSString class]]) continue;
        NSString *strValue = (NSString *)value;

        if ([key isEqualToString:AVMetadataCommonKeyTitle]) {
            result.title = strValue;
        } else if ([key isEqualToString:AVMetadataCommonKeyArtist]) {
            result.artist = strValue;
        } else if ([key isEqualToString:AVMetadataCommonKeyAlbumName]) {
            result.album = strValue;
            // Note: no standard AVMetadataCommonKey for albumArtist;
            // album artist is read from ID3 TPE2 frame directly
        }
    }

    // Apply encoding detection to AVAsset results too
    // (AVAsset may also have encoding issues)
    if (IsLikelyMojibake(result.title)) result.title = FixMojibake(result.title);
    if (IsLikelyMojibake(result.artist)) result.artist = FixMojibake(result.artist);
    if (IsLikelyMojibake(result.album)) result.album = FixMojibake(result.album);
    if (IsLikelyMojibake(result.albumArtist)) result.albumArtist = FixMojibake(result.albumArtist);

    return result;
}

@end
