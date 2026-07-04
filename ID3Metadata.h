// ID3Metadata.h — ID3 tag parser with automatic encoding detection
// Supports ID3v1, ID3v2.3, ID3v2.4 with UTF-8, UTF-16, Windows-1251, ISO-8859-1

#import <Foundation/Foundation.h>

@interface ID3MetadataResult : NSObject
@property (strong) NSString *title;
@property (strong) NSString *artist;
@property (strong) NSString *album;
@property (strong) NSString *albumArtist;
@property (strong) NSString *genre;
@property (assign) NSTimeInterval duration;
@end

@interface ID3Parser : NSObject

/// Parse metadata from an audio file using direct ID3 tag reading.
/// Falls back to AVURLAsset if no ID3 tags are found.
+ (ID3MetadataResult *)parseMetadataFromURL:(NSURL *)url;

/// Parse only from ID3v2 tag bytes (returns nil if no ID3v2 found).
+ (ID3MetadataResult *)parseID3v2FromData:(NSData *)fileData;

/// Parse only from ID3v1 tag bytes (returns nil if no ID3v1 found).
+ (ID3MetadataResult *)parseID3v1FromData:(NSData *)fileData;

/// Enable/disable debug logging of encoding decisions.
+ (void)setDebugMode:(BOOL)enabled;

/// Clear cached decoding results.
+ (void)clearCache;

/// Get the detected encoding for a specific field (debug).
+ (NSString *)detectedEncodingForURL:(NSURL *)url field:(NSString *)field;

@end
