require 'net/http'
require 'json'
require 'uri'

class ZakkiStore
  attr_accessor :base_url, :token, :iduser, :email, :pin, :auto_withdraw

  def initialize(base_url = "https://qris.zakki.store", token = nil, iduser = nil, email = nil, pin = nil, auto_withdraw = false)
    # Smart detection if token is placed in base_url parameter
    if base_url && !base_url.start_with?("http://") && !base_url.start_with?("https://") && token.nil?
      token = base_url
      base_url = "https://qris.zakki.store"
    end

    raise ArgumentError, "token wajib disertakan dalam konfigurasi SDK." if token.nil? || token.empty?
    raise ArgumentError, "base_url wajib disertakan dalam konfigurasi SDK." if base_url.nil? || base_url.empty?

    @base_url = base_url.chomp('/')
    @token = token
    @iduser = iduser
    @email = email
    @pin = pin
    @auto_withdraw = !!auto_withdraw
  end

  def enable_auto_withdraw(status)
    @auto_withdraw = !!status
  end

  def enableAutoWithdraw(status)
    enable_auto_withdraw(status)
  end

  # ==========================================================
  # --- 1. PAYMENT GATEWAY (QRIS TOPUP) ---
  # ==========================================================

  def topup(nominal)
    _request('/topup', 'POST', {
      "token" => @token,
      "nominal" => nominal.to_i
    })
  end

  def cektopup(idtopup)
    _request('/cektopup', 'GET', {
      "idtopup" => idtopup
    })
  end

  def cancel(id_transaksi = nil, all_pending = false)
    if id_transaksi.is_a?(TrueClass) || id_transaksi.is_a?(FalseClass)
      all_pending = id_transaksi
      id_transaksi = nil
    end

    payload = { "token" => @token }
    payload["id_transaksi"] = id_transaksi if id_transaksi
    payload["all"] = true if all_pending
    _request('/cancel', 'POST', payload)
  end

  # ==========================================================
  # --- 2. TRANSAKSI H2H (HOST-TO-HOST) ---
  # ==========================================================

  def listkode(jenis = nil, product_type = nil)
    payload = {}
    payload["jenis"] = jenis if jenis
    payload["type"] = product_type if product_type
    _request('/listkode', 'GET', payload)
  end

  def h2h(kode, tujuan = nil, ref_id = nil)
    if kode.is_a?(Hash)
      payload = kode
      kode = payload[:kode] || payload["kode"]
      tujuan = payload[:tujuan] || payload["tujuan"]
      ref_id = payload[:refID] || payload["refID"] || payload[:ref_id] || payload["ref_id"]
    end

    _request('/h2h', 'POST', {
      "token" => @token,
      "kode" => kode,
      "tujuan" => tujuan,
      "refID" => ref_id
    })
  end

  def cekh2h(id_trx)
    _request('/cekh2h', 'GET', { "id" => id_trx })
  end

  def myh2h
    _request('/myh2h', 'GET', { "token" => @token })
  end

  # ==========================================================
  # --- 3. PERBANKAN & TRANSFER SALDO ---
  # ==========================================================

  def checkbank
    payload = { "token" => @token }
    payload["iduser"] = @iduser if @iduser
    payload["email"] = @email if @email

    bank_res = _request('/checkbank', 'GET', payload)

    if @auto_withdraw && bank_res["data"] && bank_res["data"]["bank_detail"]
      bank_detail = bank_res["data"]["bank_detail"]
      balance = (bank_detail["balance"] || 0).to_f

      if balance > 0
        begin
          withdraw_res = tarik(balance.to_i)
          bank_res = _request('/checkbank', 'GET', payload)
          bank_res["auto_withdraw_executed"] = true
          bank_res["auto_withdraw_amount"] = balance.to_i
          bank_res["auto_withdraw_message"] = withdraw_res["message"] || "Auto-withdraw berhasil dijalankan."
        rescue => err
          bank_res["auto_withdraw_executed"] = false
          bank_res["auto_withdraw_error"] = err.message
        end
      end
    end

    bank_res
  end

  def checkname(number)
    _request('/checkname', 'GET', { "number" => number.to_s.strip })
  end

  def transfer(to, amount = nil)
    if to.is_a?(Hash)
      payload = to
      to = payload[:to] || payload["to"]
      amount = payload[:amount] || payload["amount"]
    end

    _request('/transfer', 'POST', {
      "token" => @token,
      "to" => to,
      "amount" => amount.to_i
    })
  end

  def tabung(jumlah)
    raise RuntimeError, "[ZakkiStore SDK Error] PIN transaksi diperlukan untuk melakukan transaksi tabung." unless @pin
    payload = {
      "token" => @token,
      "jumlah" => jumlah.to_i,
      "pin" => @pin
    }
    payload["iduser"] = @iduser if @iduser
    payload["email"] = @email if @email
    _request('/tabung', 'POST', payload)
  end

  def tarik(jumlah)
    raise RuntimeError, "[ZakkiStore SDK Error] PIN transaksi diperlukan untuk melakukan transaksi tarik." unless @pin
    payload = {
      "token" => @token,
      "jumlah" => jumlah.to_i,
      "pin" => @pin
    }
    payload["iduser"] = @iduser if @iduser
    payload["email"] = @email if @email
    _request('/tarik', 'POST', payload)
  end

  def checkmutasi(mutasi_type = "all")
    payload = {
      "token" => @token,
      "type" => mutasi_type
    }
    payload["iduser"] = @iduser if @iduser
    payload["email"] = @email if @email
    _request('/checkmutasi', 'GET', payload)
  end

  # ==========================================================
  # --- 4. NOKTEL MARKETPLACE (OTP VIRTUAL) ---
  # ==========================================================

  def noktelStok
    _request('/noktel/stok', 'GET', { "token" => @token })
  end

  def noktelBuy(category)
    _request('/noktel/buy', 'POST', {
      "token" => @token,
      "category" => category.to_s.strip
    })
  end

  def noktelGetOtp(account_id)
    _request('/noktel/getotp', 'GET', {
      "token" => @token,
      "account_id" => account_id.to_s.strip
    })
  end

  def noktelCancel(invoice_id)
    _request('/noktel/cancel', 'POST', {
      "token" => @token,
      "invoice_id" => invoice_id.to_s.strip
    })
  end

  def noktelHistory
    _request('/noktel/history', 'GET', { "token" => @token })
  end

  # ==========================================================
  # --- 5. REWARD KOMPUTASI & UTILITY ---
  # ==========================================================

  def cekmining(idmining)
    raise ArgumentError, "Parameter idmining wajib diisi." if idmining.nil? || idmining.empty?
    _request('/cekmining', 'GET', { "idmining" => idmining.to_s.strip })
  end

  def mymining
    _request('/mymining', 'GET', { "token" => @token })
  end

  def mining_start
    _request('/mining/start', 'GET', { "token" => @token })
  end

  def miningStart
    mining_start
  end

  def mining_submit(nonce, signature)
    raise ArgumentError, "Parameter nonce wajib disertakan." if nonce.nil?
    raise ArgumentError, "Parameter signature wajib disertakan." if signature.nil? || signature.empty?
    _request('/mining/submit', 'POST', {
      "token" => @token,
      "nonce" => nonce,
      "signature" => signature
    })
  end

  def miningSubmit(nonce, signature)
    mining_submit(nonce, signature)
  end

  def cekgacha
    _request('/cekgacha', 'GET', { "token" => @token })
  end

  # ==========================================================
  # --- 6. UTILITY & SECURITY ---
  # ==========================================================

  def whitelistip(ip)
    _request('/whitelistip', 'POST', {
      "token" => @token,
      "ip" => ip.to_s.strip
    })
  end

  def delwhitelistip(ip)
    _request('/delwhitelistip', 'POST', {
      "token" => @token,
      "ip" => ip.to_s.strip
    })
  end

  def leaderboard(limit = 10, period = "all")
    _request('/leaderboard', 'GET', {
      "limit" => limit.to_i,
      "period" => period.to_s.strip
    })
  end

  def status
    _request('/status', 'GET')
  end

  # ==========================================================
  # --- 7. METODE INTEGRASI BARU ---
  # ==========================================================

  def set_callback(site)
    _request('/setcallback', 'GET', {
      "token" => @token,
      "site" => site.to_s.strip
    })
  end

  def setcallback(site)
    set_callback(site)
  end

  def del_callback
    _request('/delcallback', 'GET', { "token" => @token })
  end

  def delcallback
    del_callback
  end

  def set_notif_bot(telegram_id)
    _request('/setnotifbot', 'GET', {
      "token" => @token,
      "id" => telegram_id.to_s.strip
    })
  end

  def setnotifbot(telegram_id)
    set_notif_bot(telegram_id)
  end

  def del_notif_bot
    _request('/delnotifbot', 'GET', { "token" => @token })
  end

  def delnotifbot
    del_notif_bot
  end

  def check_transfer(idtransfer)
    _request('/checktransfer', 'GET', { "idtransfer" => idtransfer.to_s.strip })
  end

  def checktransfer(idtransfer)
    check_transfer(idtransfer)
  end

  def my_transfer(transfer_type = "all")
    _request('/mytransfer', 'GET', {
      "token" => @token,
      "type" => transfer_type.to_s.strip
    })
  end

  def mytransfer(transfer_type = "all")
    my_transfer(transfer_type)
  end

  def my_topup
    _request('/mytopup', 'GET', { "token" => @token })
  end

  def mytopup
    my_topup
  end

  def cek_my_ip
    _request('/cekmyip', 'GET')
  end

  def cekmyip
    cek_my_ip
  end

  def cek_ip(ip)
    _request('/cekip', 'GET', { "ip" => ip.to_s.strip })
  end

  def cekip(ip)
    cek_ip(ip)
  end

  private

  def _request(endpoint, method = 'GET', data = nil)
    uri = URI.parse("#{@base_url}#{endpoint}")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == 'https'

    headers = { 'Content-Type' => 'application/json' }

    if method.upcase == 'GET'
      if data && !data.empty?
        uri.query = URI.encode_www_form(data)
      end
      request = Net::HTTP::Get.new(uri.request_uri, headers)
    else
      request = Net::HTTP::Post.new(uri.request_uri, headers)
      request.body = data.to_json if data
    end

    begin
      response = http.request(request)
      res_json = JSON.parse(response.body) rescue { "message" => response.body }

      if response.code.to_i != 200 && response.code.to_i != 201
        err_msg = res_json["message"] || "HTTP Error! Status: #{response.code}"
        if response.code.to_i == 403 || err_msg.downcase.include?("ip")
          err_msg += "\n⚠️ [IP BLOCKED / UNREGISTERED] IP Anda diblokir atau belum terdaftar di whitelist API. Silakan hubungi developer via WhatsApp (https://wa.me/6283844082339) atau Telegram (https://t.me/zakki_store) untuk mendapatkan bantuan."
        end
        raise RuntimeError, "[ZakkiStore SDK Error] #{err_msg}"
      end

      res_json
    rescue => e
      raise RuntimeError, "[ZakkiStore SDK Error] Koneksi Gagal: #{e.message}"
    end
  end
end
