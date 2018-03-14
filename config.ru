require 'debci/api'

LISTING = <<EOF
<!DOCTYPE html>
<html>
  <body>
  <h1>Index of <%= request.path %></h1>
  <div><a href="..">..</a></div>
  <% Dir.chdir(@dir) do %>
    <% Dir.glob('*').each do |f| %>
      <% h = File.directory?(f) ? f + '/': f %>
      <div><a href="<%= h %>"><%= f %></a></div>
    <% end %>
  <% end %>
  </body>
</html>
EOF

class ServeStatic < Sinatra::Base
  get '/*' do
    if request.path !~ %r{/$}
      return redirect(request.path + '/')
    end
    index = File.join(settings.public_folder, request.path, 'index.html')
    if File.exist?(index)
      send_file(index, type: 'text/html')
    else
      @dir = File.dirname(index)
      if File.directory?(@dir)
        erb LISTING
      else
        halt(404, "<h1>404 Not Found</h1>")
      end
    end
  end
end

app = Rack::Builder.new do
  run ServeStatic
  map '/api' do
    run Debci::API
  end
end

run app
