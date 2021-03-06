from os import path

import pytest

from client import client_output
from client.client import Client
from tools.paths import ACCOUNT_PATH, CONTRACT_PATH
from tools.utils import assert_run_failure

BAKE_ARGS = ['--max-priority', '512', '--minimal-timestamp']
TRANSFER_ARGS = ['--burn-cap', '0.257']


@pytest.mark.incremental
class TestRawContext:

    def test_delegates(self, client: Client):
        path = ('/chains/main/blocks/head/context/raw/bytes/baker/registered/'
                '?depth=3')
        res = client.rpc('get', path)
        expected = {
            '2a': {'47': {'53': None}},
            'b3': {'1b': {'a9': None}},
            'c2': {'c0': {'08': None}},
            'dd': {'57': {'7f': None}},
            'ef': {'24': {'71': None}}
        }
        assert res == expected

    def test_no_service_1(self, client: Client):
        path = '/chains/main/blocks/head/context/raw/bytes/non-existent'
        with pytest.raises(client_output.InvalidClientOutput) as exc:
            client.rpc('get', path)
        assert exc.value.client_output == 'No service found at this URL\n\n'

    def test_no_service_2(self, client: Client):
        path = ('/chains/main/blocks/head/context/raw/bytes/'
                'non-existent?depth=-1')
        with pytest.raises(client_output.InvalidClientOutput) as exc:
            client.rpc('get', path)
        expected = 'Command failed : Extraction depth -1 is invalid\n\n'
        assert exc.value.client_output == expected

    def test_no_service_3(self, client: Client):
        path = ('/chains/main/blocks/head/context/raw/bytes/'
                'non-existent?depth=0')
        with pytest.raises(client_output.InvalidClientOutput) as exc:
            client.rpc('get', path)
        assert exc.value.client_output == 'No service found at this URL\n\n'

    def test_bake(self, client: Client):
        client.bake('baker4', BAKE_ARGS)

    @pytest.mark.parametrize(
        "identity, message, expected_signature",
        [('bootstrap1', 'msg1',
          'edsigtZHRixK8wxudi71uVFGKhD9psBCKEVKjocZ6iTUmXD7GUb8Kr78MZk3bZmwA9K'
          'xUb4LaGK4djK6mELFizi7gHXEJmJE9Mq'),
         ('bootstrap2', 'msg2',
          'edsigtYRSNM9ayrAhHzdrjkoGgHRZfPSDmr7nijuNEwMm3rrtoeTLdMGygGJeoikP6T'
          'C6ApppWzXK2kiujoRQ7oea5ZjTAvXU2m'),
         ('bootstrap3', 'msg3',
          'edsigtreUCu9SycaDnvKT3tYGzx9Jd4guqDnxcx8Q1wwrsaiKsG4xkmkwjsoyGgRbKN'
          'sy89texWneLPtD5PmGb8idEmWucecYDP'),
         ('bootstrap4', 'msg4',
          'edsigttaHYfYhmWFQPkQztHTE5tSfXuCskFLZ5yzLTyRvJjs3MKPziurLPHt6Ct2sZu'
          'XTHziprFvsei3ExeU36v7A3EsasaKNkG')])
    def test_sign_message(self, client, identity, message,
                          expected_signature):
        assert client.sign_message(message, identity) == expected_signature

    @pytest.mark.parametrize(
        "identity, message, signature",
        [('bootstrap1', 'msg1',
          'edsigtZHRixK8wxudi71uVFGKhD9psBCKEVKjocZ6iTUmXD7GUb8Kr78MZk3bZmwA9K'
          'xUb4LaGK4djK6mELFizi7gHXEJmJE9Mq'),
         ('bootstrap2', 'msg2',
          'edsigtYRSNM9ayrAhHzdrjkoGgHRZfPSDmr7nijuNEwMm3rrtoeTLdMGygGJeoikP6T'
          'C6ApppWzXK2kiujoRQ7oea5ZjTAvXU2m'),
         ('bootstrap3', 'msg3',
          'edsigtreUCu9SycaDnvKT3tYGzx9Jd4guqDnxcx8Q1wwrsaiKsG4xkmkwjsoyGgRbKN'
          'sy89texWneLPtD5PmGb8idEmWucecYDP'),
         ('bootstrap4', 'msg4',
          'edsigttaHYfYhmWFQPkQztHTE5tSfXuCskFLZ5yzLTyRvJjs3MKPziurLPHt6Ct2sZu'
          'XTHziprFvsei3ExeU36v7A3EsasaKNkG')])
    def test_check_message(self, client, identity, message,
                           signature):
        assert client.check_message(message, identity, signature)

    @pytest.mark.parametrize(
        "identity, message, head_block",
        [("bootstrap1", "msg1", False),
         ("bootstrap2", "msg2", False),
         ("bootstrap3", "msg3", True),
         ("bootstrap4", "msg4", True)])
    def test_fail_inject_signed_arbitrary_ope(self, client, identity, message,
                                              head_block):
        if head_block:
            signature = client.sign_message(message, identity, block="head")
        else:
            signature = client.sign_message(message, identity)
        chain_id = client.rpc('get', '/chains/main/chain_id')
        head_hash = client.rpc('get', '/chains/main/blocks/head/hash')
        run_json = {'operation':
                    {"branch": head_hash,
                     "contents": [
                         {"kind": "failing_noop",
                          "arbitrary": message}],
                     'signature': signature},
                    'chain_id': chain_id}
        run_operation_path = ('/chains/main/blocks/head/helpers/scripts/'
                              'run_operation')
        with pytest.raises(client_output.InvalidClientOutput) as exc:
            client.rpc('post', run_operation_path, data=run_json)
        assert exc.value.client_output == ('Command failed : The failing_noop '
                                           'operation cannot be executed by '
                                           'the protocol\n\n')

    def test_gen_keys(self, client: Client, session):
        session['keys'] = ['foo', 'bar', 'boo']
        sigs = [None, 'secp256k1', 'ed25519']
        for key, sig in zip(session['keys'], sigs):
            args = [] if sig is None else ['--sig', sig]
            client.gen_key(key, args)

    def test_transfers(self, client: Client, session):
        client.transfer(1000, 'bootstrap1',
                        session['keys'][0],
                        TRANSFER_ARGS)
        client.bake('baker1', BAKE_ARGS)
        client.transfer(2000, 'bootstrap1',
                        session['keys'][1],
                        TRANSFER_ARGS)
        client.bake('baker1', BAKE_ARGS)
        client.transfer(3000, 'bootstrap1',
                        session['keys'][2],
                        TRANSFER_ARGS)
        client.bake('baker1', BAKE_ARGS)

    def test_balances(self, client: Client, session):
        assert client.get_balance(session['keys'][0]) == 1000
        assert client.get_balance(session['keys'][1]) == 2000
        assert client.get_balance(session['keys'][2]) == 3000

    def test_transfer_bar_foo(self, client: Client, session):
        client.transfer(1000, session['keys'][1], session['keys'][0],
                        ['--fee', '0', '--force-low-fee'])
        client.bake('baker1', BAKE_ARGS +
                    ['--minimal-fees', '0', '--minimal-nanotez-per-byte',
                     '0', '--minimal-nanotez-per-gas-unit', '0'])

    def test_balances_bar_foo(self, client: Client, session):
        assert client.get_balance(session['keys'][0]) == 2000
        assert client.get_balance(session['keys'][1]) == 1000

    def test_transfer_foo_bar(self, client: Client, session):
        client.transfer(1000, session['keys'][0],
                        session['keys'][1],
                        ['--fee', '0.05'])
        client.bake('baker1', BAKE_ARGS)

    def test_balances_foo_bar(self, client: Client, session):
        assert client.get_balance(session['keys'][0]) == 999.95
        assert client.get_balance(session['keys'][1]) == 2000

    def test_transfer_failure(self, client: Client, session):
        with pytest.raises(Exception):
            client.transfer(999.95, session['keys'][0], session['keys'][1])

    def test_originate_contract_noop(self, client: Client):
        contract = path.join(CONTRACT_PATH, 'opcodes', 'noop.tz')
        client.remember('noop', contract)
        client.typecheck(contract)
        client.originate('noop',
                         1000, 'bootstrap1', contract,
                         ['--burn-cap', '0.295'])
        client.bake('baker1', BAKE_ARGS)

    def test_transfer_to_noop(self, client: Client):
        client.transfer(10, 'bootstrap1', 'noop',
                        ['--arg', 'Unit'])
        client.bake('baker1', BAKE_ARGS)

    def test_contract_hardlimit(self, client: Client):
        contract = path.join(CONTRACT_PATH, 'mini_scenarios', 'hardlimit.tz')
        client.originate('hardlimit',
                         1000, 'bootstrap1',
                         contract,
                         ['--init', '3',
                          '--burn-cap', '0.341'])
        client.bake('baker1', BAKE_ARGS)
        client.transfer(10, 'bootstrap1',
                        'hardlimit',
                        ['--arg', 'Unit'])
        client.bake('baker1', BAKE_ARGS)
        client.transfer(10, 'bootstrap1',
                        'hardlimit',
                        ['--arg', 'Unit'])
        client.bake('baker1', BAKE_ARGS)

    def test_transfers_bootstraps5_bootstrap1(self, client: Client):
        assert client.get_balance('bootstrap5') == 4000000
        client.transfer(400000, 'bootstrap5',
                        'bootstrap1',
                        ['--fee', '0',
                         '--force-low-fee'])
        client.bake('baker1', BAKE_ARGS)
        client.transfer(400000, 'bootstrap1',
                        'bootstrap5',
                        ['--fee', '0',
                         '--force-low-fee'])
        client.bake('baker1', BAKE_ARGS)
        assert client.get_balance('bootstrap5') == 4000000

    def test_activate_accounts(self, client: Client, session):
        account = f"{ACCOUNT_PATH}/king_commitment.json"
        session['keys'] += ['king', 'queen']
        client.activate_account(session['keys'][3], account)
        client.bake('baker1', BAKE_ARGS)
        account = f"{ACCOUNT_PATH}/queen_commitment.json"
        client.activate_account(session['keys'][4], account)
        client.bake('baker1', BAKE_ARGS)
        assert client.get_balance(session['keys'][3]) == 23932454.669343
        assert client.get_balance(session['keys'][4]) == 72954577.464032

    def test_transfer_king_queen(self, client: Client, session):
        keys = session['keys']
        client.transfer(10, keys[3], keys[4], TRANSFER_ARGS)
        client.bake('baker1', BAKE_ARGS)

    def test_duplicate_alias(self, client: Client):
        client.add_address("baz", "foo", force=True)
        show_foo = client.show_address("foo", show_secret=True)
        assert show_foo.secret_key is not None


class TestRememberContract:
    @pytest.mark.parametrize(
        "contract_name,non_originated_contract_address", [
            ("test",
             "KT1BuEZtb68c1Q4yjtckcNjGELqWt56Xyesc"),
            ("test-2",
             "KT1TZCh8fmUbuDqFxetPWC2fsQanAHzLx4W9"),
        ])
    def test_non_originated_contract_no_forcing_not_saved_before(
            self,
            client,
            contract_name,
            non_originated_contract_address,
    ):
        client.remember_contract(contract_name,
                                 non_originated_contract_address)

    # As it is always the same client, the contracts have been saved
    # before
    @pytest.mark.parametrize(
        "contract_name,non_originated_contract_address", [
            ("test",
             "KT1BuEZtb68c1Q4yjtckcNjGELqWt56Xyesc"),
            ("test-2",
             "KT1TZCh8fmUbuDqFxetPWC2fsQanAHzLx4W9"),
        ])
    def test_non_originated_contract_with_forcing_and_saved_before(
            self,
            client,
            contract_name,
            non_originated_contract_address,
    ):
        client.remember_contract(contract_name,
                                 non_originated_contract_address,
                                 force=True)

    # As it is always the same client, the contracts have been saved
    # before
    @pytest.mark.parametrize(
        "contract_name,non_originated_contract_address", [
            ("test",
             "KT1BuEZtb68c1Q4yjtckcNjGELqWt56Xyesc"),
            ("test-2",
             "KT1TZCh8fmUbuDqFxetPWC2fsQanAHzLx4W9"),
        ])
    def test_non_originated_contract_no_forcing_and_saved_before(
            self,
            client,
            contract_name,
            non_originated_contract_address,
    ):
        expected_error = f"The contract alias {contract_name} already exists"

        with assert_run_failure(expected_error):
            client.remember_contract(contract_name,
                                     non_originated_contract_address,
                                     force=False)
