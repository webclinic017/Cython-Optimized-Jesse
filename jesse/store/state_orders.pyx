from typing import List

import pydash

from jesse.config import config
from jesse.models import Order
from jesse.enums import order_statuses
# from jesse.services import selectors
import jesse.helpers as jh
from cpython cimport * 

cdef extern from "Python.h":
        Py_ssize_t PyList_GET_SIZE(object list)

class OrdersState:
    def __init__(self) -> None:
        # used in simulation only
        self.to_execute:list = []

        self.storage:dict = {}

        for exchange in config['app']['trading_exchanges']:
            for symbol in config['app']['trading_symbols']:
                key = f'{exchange}-{symbol}'
                self.storage[key] = []

    def reset(self) -> None:
        """
        used for testing
        """
        for key in self.storage:
            self.storage[key].clear()

    def reset_trade_orders(self, exchange: str, symbol: str) -> None:
        """
        used after each completed trade
        """
        key = f'{exchange}-{symbol}'
        self.storage[key] = []

    def add_order(self, order: Order) -> None:
        key = f'{order.exchange}-{order.symbol}'
        self.storage[key].append(order)

    def remove_order(self, order: Order) -> None:
        key = f'{order.exchange}-{order.symbol}'
        self.storage[key] = [
            o for o in self.storage[key] if o.id != order.id
        ]

    def execute_pending_market_orders(self) -> None:
        # if PyList_GET_SIZE(self.to_execute) == 0:
            # return

        for o in self.to_execute:
            o.execute()

        self.to_execute = []

    # # # # # # # # # # # # # # # # #
    # getters
    # # # # # # # # # # # # # # # # #
    
    def get_orders(self, exchange, symbol) -> List[Order]:
        key = f'{exchange}-{symbol}'
        return self.storage.get(key, [])
        
    def get_all_orders(self, exchange: str) -> List[Order]:
        return [o for key in self.storage for o in self.storage[key] if o.exchange == exchange]
        
    def count_all_active_orders(self) -> int:
        cdef Py_ssize_t c 
        c = 0
        for key in self.storage:
            if len(self.storage[key]):
                for o in self.storage[key]:
                    if o.status == order_statuses.ACTIVE:
                        c += 1
        return c

    def count_active_orders(self, exchange: str, symbol: str) -> int:
        orders = self.storage.get(f'{exchange}-{symbol}', [])
        return sum(bool(o.status == order_statuses.ACTIVE) for o in orders)

    def count(self, exchange: str, symbol: str) -> int:
       return len(self.storage.get(f'{exchange}-{symbol}', []))

    def get_order_by_id(self, exchange: str, symbol: str, id: str, use_exchange_id: bool = False) -> Order:
        key = f'{exchange}-{symbol}'

        if use_exchange_id:
            return pydash.find(self.storage[key], lambda o: o.exchange_id == id)

        return pydash.find(self.storage[key], lambda o: o.id == id)


    def get_entry_orders(self, exchange: str, symbol: str) -> List[Order]:
        all_orders = self.get_orders(exchange, symbol)
        # return empty if no orders
        if len(all_orders) == 0:
            return []
        # return all orders if position is not opened yet
        from jesse.store import store
        key = f'{exchange}-{symbol}'
        p = store.positions.storage.get(key, None)
        if p.qty == 0 :
            entry_orders = all_orders.copy()
        else:
            entry_orders = [o for o in all_orders if o.side == jh.type_to_side(p.type)]

        # exclude cancelled orders
        entry_orders = [o for o in entry_orders if not o.is_canceled]

        return entry_orders

    def get_exit_orders(self, exchange: str, symbol: str) -> List[Order]:
        """
        excludes cancel orders but includes executed orders
        """
        all_orders = self.get_orders(exchange, symbol)
        # return empty if no orders
        if len(all_orders) == 0:
            return []
        # return empty if position is not opened yet
        from jesse.store import store
        key = f'{exchange}-{symbol}'
        p = store.positions.storage.get(key, None)
        if p.qty == 0:
            return []
        else:
            exit_orders = [o for o in all_orders if o.side != jh.type_to_side(p.type)]

        # exclude cancelled orders
        exit_orders = [o for o in exit_orders if not o.is_canceled]

        return exit_orders