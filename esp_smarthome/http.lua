------------------------------------------------------------------------------
-- HTTP server module
--
-- LICENCE: http://opensource.org/licenses/MIT
-- Vladimir Dronnikov <dronnikov@gmail.com>
------------------------------------------------------------------------------
local collectgarbage, tonumber, tostring = collectgarbage, tonumber, tostring

local http
do
  ------------------------------------------------------------------------------
  -- request methods
  ------------------------------------------------------------------------------
  local make_req = function(conn, method, url)
    local req = {
      conn = conn,
      method = method,
      url = url,
    }
    -- return setmetatable(req, {
    -- })
    return req
  end

  ------------------------------------------------------------------------------
  -- response methods
  ------------------------------------------------------------------------------
  local tobuff = function(s, t)
    s.buff = s.buff..t
  end
  
  local init = function(s, status)
    -- TODO: req.send should take care of response headers!
    s:tobuff("HTTP/1.1 ")
    s:tobuff(tostring(status or 200))
    -- TODO: real HTTP status code/name table
    s:tobuff(" OK\r\n")
    -- we use chunked transfer encoding, to not deal with Content-Length:
    --   response header
    s:send_header("Transfer-Encoding", "chunked")
    -- TODO: send standard response headers, such as Server:, Date:
  end
  local send_header = function(s, name, value)
    -- NB: quite a naive implementation
    s:tobuff(name..": "..value.."\r\n")
  end
  local send = function(s, data, status)
    -- NB: no headers allowed after response body started
    if s.send_header then
      s.send_header = nil
      -- end response headers
      s:tobuff("\r\n")
    end
    -- chunked transfer encoding
    s:tobuff(("%X\r\n"):format(#data))
    s:tobuff(data)
    s:tobuff("\r\n")
  end
  -- finalize request, optionally sending data
  local finish = function(s, data, status)
    local c = s.conn
    -- NB: req.send takes care of response headers
    if data then
      s:tobuff(data, status)
    end
    -- finalize chunked transfer encoding
    s:tobuff("0\r\n\r\n")
    
    c:send(s.buff)
    s.buff = ''
    -- close connection
    c:close()
  end
  --
  local make_res = function(conn)
    local res = {
      conn = conn,
      buff = '',
    }
    -- return setmetatable(res, {
    --  send_header = send_header,
    --  send = send,
    --  finish = finish,
    -- })
    res.init = init
    res.send_header = send_header
    res.send = send
    res.tobuff = tobuff
    res.finish = finish
    return res
  end

  ------------------------------------------------------------------------------
  -- HTTP parser
  ------------------------------------------------------------------------------
  local http_handler = function(handler)
    return function(conn)
      local req, res
      local method, url
      local ondisconnect = function(conn)
        --collectgarbage("collect")
      end
      -- header parser
      local cnt_len = 0
      -- body data handler
      local onreceive = function(conn, buf)
        -- consume buffer line by line
        while #buf > 0 do
          -- extract line
          local e = buf:find("\r\n", 1, true)
          if not e then break end
          local line = buf:sub(1, e - 1)
          buf = buf:sub(e + 2)
          -- method, url?
          if not method then
            local i
            -- NB: just version 1.1 assumed
            _, i, method, url = line:find("^([A-Z]+) (.-) HTTP/1.1$")
            if method then
              -- make request and response objects
              req = make_req(conn, method, url)
              res = make_res(conn)
            end
          -- header line?
          elseif #line > 0 then
          -- headers end
          else
            -- spawn request handler
            -- NB: do not reset in case of lengthy requests
            if not pcall(function () handler(req, res) end) then
                res:send('FAIL')
                res:finish()
            end
            -- NB: we feed the rest of the buffer as starting chunk of body
            buf = nil
            req = nil
            res = nil
            break
          end
        end
      end
      conn:on("receive", onreceive)
      conn:on("disconnection", ondisconnect)
    end
  end

  ------------------------------------------------------------------------------
  -- HTTP server
  ------------------------------------------------------------------------------
  local srv
  local createServer = function(port, handler)
    -- NB: only one server at a time
    if srv then srv:close() end
    srv = net.createServer(net.TCP, 15)
    -- listen
    srv:listen(port, http_handler(handler))
    return srv
  end

  ------------------------------------------------------------------------------
  -- HTTP server methods
  ------------------------------------------------------------------------------
  http = {
    createServer = createServer,
  }
end

return http
