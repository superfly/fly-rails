def build_gems
  system 'rake -f lib/tasks/fly.rake fly:build_gems'
end