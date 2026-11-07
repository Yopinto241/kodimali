"""Integration and race checks. Requires a migrated, isolated LOCAL database.

Set KODIMALI_LODGE_TEST_DSN outside the repository. Never run on production.
"""
import concurrent.futures
import datetime as dt
import json
import os
from pathlib import Path
import threading
import uuid
import psycopg
from psycopg.types.json import Jsonb
from psycopg.conninfo import conninfo_to_dict

ROOT = Path(__file__).resolve().parents[1]


def connection_args():
    args = conninfo_to_dict(os.environ['KODIMALI_LODGE_TEST_DSN'])
    if args.get('host') not in ('127.0.0.1', 'localhost', '::1') or not args.get('dbname', '').startswith('kodimali_lodges_'):
        raise RuntimeError('Tests require an isolated local kodimali_lodges_* database.')
    return args


def command(conn, lodge, action, data):
    return conn.execute('select public.lodge_command(%s,%s,%s::jsonb)', (lodge, action, json.dumps(data))).fetchone()[0]


def fixture(args):
    owner, other, admin = [str(uuid.uuid4()) for _ in range(3)]
    with psycopg.connect(**args) as conn:
        for uid, name in [(owner, 'Lodge browser owner'), (other, 'Other lodge owner'), (admin, 'Lodge review admin')]:
            conn.execute('insert into auth.users(id,email,raw_user_meta_data) values(%s,%s,%s::jsonb)', (uid, uid+'@example.invalid', json.dumps({'full_name': name})))
            conn.execute('insert into public.profiles(id,full_name) values(%s,%s) on conflict(id) do nothing', (uid, name))
        conn.execute("insert into public.admin_role_assignments(user_id,role_id) values(%s,'super_admin')", (admin,))
        conn.execute("select set_config('request.jwt.claim.sub',%s,true)", (owner,))
        loc = conn.execute("select id from public.locations where is_active order by (location_type='ward') desc limit 1").fetchone()[0]
        lodge = str(conn.execute('select public.lodge_register(%s::jsonb)', (json.dumps({'name': 'Local Lodge Test', 'location_id': str(loc), 'location_label': 'Arusha test location', 'phone': '255700000001', 'facilities': ['WiFi', 'Parking']}),)).fetchone()[0])
        room_type = command(conn, lodge, 'save_room_type', {'name':'Standard','max_occupancy':2,'nightly_rate':10000,'currency':'TZS'})['id']
        room = command(conn, lodge, 'save_room', {'room_type_id':room_type,'code': 'RACE-1', 'room_type': 'Standard', 'beds': 'Double bed', 'max_occupancy': 2, 'nightly_rate': 10000, 'currency': 'TZS'})['id']
        conn.execute("select set_config('request.jwt.claim.sub',%s,true)", (admin,))
        command(conn, lodge, 'review', {'approved': True, 'notes': 'Isolated test fixture approval'})
    return {'owner': owner, 'other': other, 'admin': admin, 'lodge': lodge, 'room': room, 'location': str(loc)}


def run():
    args = connection_args()
    with psycopg.connect(**args, autocommit=True) as conn:
        conn.execute((ROOT/'supabase/tests/046_independent_lodges.sql').read_text(encoding='utf8'))
    f = fixture(args)
    arrival = dt.datetime.now(dt.timezone.utc).date()+dt.timedelta(days=40)
    barrier = threading.Barrier(2)

    def compete(index):
        try:
            with psycopg.connect(**args) as conn:
                conn.execute("select set_config('request.jwt.claim.sub',%s,true)", (f['owner'],))
                conn.execute('set local role authenticated')
                barrier.wait(timeout=15)
                value = command(conn, f['lodge'], 'reserve', {'request_id': str(uuid.uuid4()), 'room_ids': [f['room']], 'arrival': arrival.isoformat(), 'departure': (arrival+dt.timedelta(days=2)).isoformat(), 'guests': 1, 'guest_name': 'Race fixture '+str(index), 'channel': 'phone', 'status': 'confirmed'})
                return ('confirmed', value['ids'][0])
        except psycopg.errors.ExclusionViolation:
            return ('conflict', None)

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(compete, [1, 2]))
    assert sorted(x[0] for x in results) == ['confirmed', 'conflict'], results
    reservation = next(value for status, value in results if status == 'confirmed')
    with psycopg.connect(**args) as conn:
        conn.execute("select set_config('request.jwt.claim.sub',%s,true)", (f['owner'],))
        conn.execute('set local role authenticated')
        payload = {'request_id': str(uuid.uuid4()), 'reservation_id': reservation, 'amount': 3000, 'method': 'Cash', 'reference': 'IDEMPOTENT-'+str(uuid.uuid4())}
        first = command(conn, f['lodge'], 'record_payment', payload)
        second = command(conn, f['lodge'], 'record_payment', payload)
        assert first == second, 'Payment retry created a different record'
        corrected = command(conn, f['lodge'], 'correct_payment', {'request_id': str(uuid.uuid4()), 'id': first['id'], 'amount': 4000, 'method': 'Cash', 'reference': payload['reference'], 'reason': 'Corrected isolated fixture amount'})
        assert corrected['id'] != first['id']
        net = conn.execute('select sum(amount) from public.lodge_payments where reservation_id=%s', (reservation,)).fetchone()[0]
        assert net == 4000, 'Atomic correction did not preserve net balance'
    with psycopg.connect(**args) as conn:
        conn.execute("select set_config('request.jwt.claim.sub',%s,true)", (f['owner'],))
        conn.execute('set local role authenticated')
        room_type = conn.execute('select room_type_id from public.lodge_rooms where id=%s',(f['room'],)).fetchone()[0]
        request_date=arrival+dt.timedelta(days=20)
        requests=[]
        for i in range(2):
            requests.append(conn.execute('select public.lodge_enquire(%s,%s)',(f['lodge'],Jsonb({'room_type_id':str(room_type),'arrival':request_date.isoformat(),'departure':(request_date+dt.timedelta(days=2)).isoformat(),'guests':1,'message':'Concurrent marketplace fixture','contact_phone':'255700000000'}))).fetchone()[0])
    request_barrier=threading.Barrier(2)
    def allocate(request_id):
        try:
            with psycopg.connect(**args) as conn:
                conn.execute("select set_config('request.jwt.claim.sub',%s,true)",(f['owner'],))
                conn.execute('set local role authenticated')
                request_barrier.wait(timeout=15)
                command(conn,f['lodge'],'confirm_enquiry',{'id':str(request_id)})
                return 'confirmed'
        except psycopg.errors.ExclusionViolation:
            return 'conflict'
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        allocations=list(pool.map(allocate,requests))
    assert sorted(allocations)==['confirmed','conflict'],allocations
    out = ROOT/'tmp/lodges-20261107'
    out.mkdir(parents=True, exist_ok=True)
    (out/'browser-fixture.json').write_text(json.dumps(f), encoding='utf8')
    (out/'database-results.json').write_text(json.dumps({'local_database_only': True, 'integration_and_rls_suite': 'passed', 'concurrent_confirmations': 1, 'concurrent_conflicts': 1, 'payment_retry': 'one record', 'atomic_correction_net': 4000,'concurrent_marketplace_allocations':allocations}, indent=2), encoding='utf8')
    print('PASS: integration/RLS, concurrent booking exclusion, idempotent payment retry and atomic correction')


if __name__ == '__main__':
    run()
