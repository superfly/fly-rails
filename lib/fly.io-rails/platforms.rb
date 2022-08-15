module Fly_io
  PLATFORMS = {
    'Linux_arm64' => 'aarch64-linux',
    'Linux_x86_64' => 'x86-linux',
    'macOS_arm64' => 'arm64-darwin',
    'macOS_x86_64' => 'x86_64-darwin',
    'Windows_arm64' => nil, # Can't find a match
    'Windows_x86_64' => 'x64-mingw32'
  }
end
