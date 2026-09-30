import { NextResponse } from 'next/server';
import { db } from '@/lib/server/db';
import { verifyPin } from '@/lib/server/crypto';

export const runtime = 'nodejs';

export async function POST(req: Request) {
  try {
    const body = await req.json();
    const name = String(body.name || '').trim();
    const number = String(body.number || '').trim();
    const pin = String(body.pin || '').trim();

    if (!name || !number || !/^\d{6}$/.test(pin)) {
      return NextResponse.json({
        ok: false,
        phase: 'input'
      });
    }

    const pepper = process.env.PIN_PEPPER || '';

    const { data: identities, error: identityError } = await db()
      .from('student_verifications')
      .select('user_id,users!inner(display_name)')
      .eq('student_number', number)
      .eq('users.display_name', name)
      .order('school_year', { ascending: false })
      .limit(20);

    if (identityError) {
      return NextResponse.json({
        ok: false,
        phase: 'identity_query',
        code: identityError.code || null
      });
    }

    const ids = [...new Set((identities || []).map((x: any) => x.user_id))];

    const { data: credentials, error: credentialError } = ids.length
      ? await db().from('pin_credentials').select('user_id,pin_hash').in('user_id', ids)
      : { data: [], error: null };

    if (credentialError) {
      return NextResponse.json({
        ok: false,
        phase: 'credential_query',
        code: credentialError.code || null
      });
    }

    let matchCount = 0;
    let hashFormatOk = true;

    for (const c of credentials || []) {
      const hash = String((c as any).pin_hash || '');
      if (!/^scrypt\$[0-9a-f]+\$[0-9a-f]+$/i.test(hash)) {
        hashFormatOk = false;
        continue;
      }
      if (await verifyPin(pin, hash)) matchCount++;
    }

    return NextResponse.json({
      ok: true,
      pepperPresent: pepper.length > 0,
      pepperLength: pepper.length,
      identityCount: ids.length,
      credentialCount: (credentials || []).length,
      hashFormatOk,
      matchCount
    });
  } catch {
    return NextResponse.json({
      ok: false,
      phase: 'unexpected'
    });
  }
}
