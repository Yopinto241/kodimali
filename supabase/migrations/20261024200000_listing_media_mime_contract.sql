-- Keep deployed storage aligned with the mobile upload pipeline.
update storage.buckets
set file_size_limit = 31457280,
    allowed_mime_types = array[
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif',
      'image/heic',
      'image/heif',
      'video/mp4',
      'video/quicktime',
      'video/x-m4v'
    ]
where id = 'listing-media';
