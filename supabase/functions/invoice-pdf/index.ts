import { createClient } from "npm:@supabase/supabase-js@2";
import { PDFDocument, rgb } from "npm:pdf-lib@1.17.1";
import fontkit from "npm:@pdf-lib/fontkit@1.1.1";

const headers = { "Content-Type": "application/json" };
const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
let fontPromise: Promise<ArrayBuffer> | undefined;
function fontBytes() {
  return fontPromise ??= fetch(
    "https://raw.githubusercontent.com/notofonts/noto-fonts/main/hinted/ttf/NotoSans/NotoSans-Regular.ttf",
  ).then(async (response) => {
    if (!response.ok) throw new Error("FONT_UNAVAILABLE");
    return response.arrayBuffer();
  }).catch((error) => { fontPromise = undefined; throw error; });
}

// The endpoint accepts identifiers only; client supplied document contents are ignored.
Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return reply(405, { error: "METHOD_NOT_ALLOWED" });
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return reply(401, { error: "AUTH_REQUIRED" });
  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const scoped = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  let organizationId: string | undefined;
  let invoiceId: string | undefined;
  try {
    const { data: identity, error: authError } = await scoped.auth.getUser();
    if (authError || !identity.user) return reply(401, { error: "AUTH_REQUIRED" });
    const body = await request.json();
    organizationId = body.organization_id;
    invoiceId = body.invoice_id;
    if (!uuid.test(organizationId ?? "") || !uuid.test(invoiceId ?? "")) {
      return reply(400, { error: "INVALID_IDENTIFIERS" });
    }
    const { data: invoice, error: accessError } = await scoped.rpc("sales_invoice_detail", {
      p_organization_id: organizationId, p_invoice_id: invoiceId,
    });
    if (accessError || !invoice) return reply(403, { error: "INVOICE_UNAVAILABLE" });
    const path = `${organizationId}/${invoiceId}/v1.pdf`;
    const { data: existing, error: assetReadError } = await admin.from("file_assets")
      .select("path").eq("organization_id", organizationId).eq("invoice_id", invoiceId)
      .eq("template_version", 1).maybeSingle();
    if (assetReadError) throw new Error("ASSET_READ_FAILED");
    if (!existing) {
      const pdf = await PDFDocument.create();
      pdf.registerFontkit(fontkit);
      const font = await pdf.embedFont(await fontBytes(), { subset: true });
      pdf.setTitle(`Invoice ${invoice.invoice_number}`);
      const issued = new Date(invoice.issued_at);
      pdf.setCreationDate(issued); pdf.setModificationDate(issued);
      let page = pdf.addPage([595.28, 841.89]);
      let y = 797;
      const write = (value: unknown, size = 10) => {
        const text = String(value ?? "").replace(/[\r\n\t]+/g, " ");
        const words = text.split(" ");
        let line = "";
        const flush = () => {
          if (y < 48) { page = pdf.addPage([595.28, 841.89]); y = 797; }
          page.drawText(line, { x: 36, y, size, font, color: rgb(0.08, 0.16, 0.28) });
          y -= size + 6; line = "";
        };
        for (const word of words) {
          // Split long unbroken identifiers too.
          for (const character of word + " ") {
            if (font.widthOfTextAtSize(line + character, size) > 523) flush();
            line += character;
          }
        }
        flush();
      };
      const business = invoice.supplier_snapshot;
      const customer = invoice.recipient_snapshot;
      write(invoice.document_type === "tax_invoice" ? "Tax Invoice" :
        invoice.document_type === "bill_of_supply" ? "Bill of Supply" : "Invoice", 22);
      write(business.legal_name ?? business.name, 15);
      write([business.address?.line1, business.address?.city, business.address?.postal_code].filter(Boolean).join(", "));
      if (business.gstin) write("GSTIN: " + business.gstin);
      write("Invoice: " + invoice.invoice_number);
      write(`Issued: ${invoice.invoice_date} | Due: ${invoice.due_date}`);
      write("Place of supply: " + invoice.place_of_supply);
      write("Bill to: " + customer.name, 13);
      if (customer.billing_address) write(customer.billing_address);
      if (customer.gstin) write("GSTIN: " + customer.gstin);
      y -= 10;
      for (const [index, item] of invoice.quote_snapshot.items.entries()) {
        write(`${index + 1}. ${item.name} | HSN/SAC: ${item.hsn_sac ?? ""}`, 11);
        write(`Qty ${item.qty} ${item.unit} | Rate INR ${item.unit_price} | Discount INR ${item.discount}`);
        write(`Taxable INR ${item.taxable_value} | CGST ${item.cgst} | SGST ${item.sgst} | IGST ${item.igst}`);
        write("Line total INR " + item.total);
        y -= 6;
      }
      write("Taxable value INR " + invoice.taxable_total, 12);
      write("Tax INR " + invoice.tax_total, 12);
      write("Grand total INR " + invoice.grand_total, 16);
      write("Issued snapshot | Template v1", 8);
      const bytes = await pdf.save();
      const upload = await admin.storage.from("invoice-pdfs").upload(path, bytes, {
        contentType: "application/pdf", upsert: false,
      });
      let savedBytes = bytes;
      if (upload.error) {
        // A simultaneous request may already have stored the immutable path.
        const downloaded = await admin.storage.from("invoice-pdfs").download(path);
        if (downloaded.error || !downloaded.data) throw new Error("PDF_UPLOAD_FAILED");
        savedBytes = new Uint8Array(await downloaded.data.arrayBuffer());
      }
      const digest = await crypto.subtle.digest("SHA-256", savedBytes);
      const sha256 = Array.from(new Uint8Array(digest)).map((v) => v.toString(16).padStart(2, "0")).join("");
      const saved = await admin.from("file_assets").upsert({
        organization_id: organizationId, invoice_id: invoiceId, template_version: 1,
        bucket: "invoice-pdfs", path, mime: "application/pdf", sha256,
      }, { onConflict: "invoice_id,template_version", ignoreDuplicates: true });
      if (saved.error) throw new Error("ASSET_WRITE_FAILED");
      await admin.from("invoice_pdf_jobs").update({ status: "ready", last_error_code: null })
        .eq("organization_id", organizationId).eq("invoice_id", invoiceId).eq("template_version", 1);
    }
    // Recheck permission before minting a link after potentially slow rendering.
    const recheck = await scoped.rpc("sales_invoice_detail", {
      p_organization_id: organizationId, p_invoice_id: invoiceId,
    });
    if (recheck.error) return reply(403, { error: "INVOICE_UNAVAILABLE" });
    const signed = await admin.storage.from("invoice-pdfs").createSignedUrl(path, 60);
    if (signed.error) throw new Error("SIGNED_URL_FAILED");
    return reply(200, { url: signed.data.signedUrl, expires_in: 60, template_version: 1 });
  } catch (_) {
    return reply(500, { error: "PDF_PREPARATION_FAILED" });
  }
});
