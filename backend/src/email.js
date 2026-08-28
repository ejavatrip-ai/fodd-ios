export async function sendEmail({ to, subject, html }) {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) return false;
  const from = process.env.EMAIL_FROM || "Fodd <onboarding@resend.dev>";
  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from, to: [to], subject, html })
    });
    if (!response.ok) console.error("Resend error", response.status, await response.text());
    return response.ok;
  } catch (error) {
    console.error("Email error", error);
    return false;
  }
}
