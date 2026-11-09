from datetime import date, timedelta

import pytest

from webshop_pipeline.simulator import Batch, Simulator


def simulate(start: date, end: date) -> tuple[Simulator, Batch]:
    sim, batch, day = Simulator(seed=7), Batch(), start
    while day <= end:
        batch.extend(sim.step(day))
        day += timedelta(days=1)
    return sim, batch


@pytest.fixture(scope="session")
def history():
    """Seven simulated months, including the start of web tracking (2025-06-01)."""
    return simulate(date(2025, 1, 1), date(2025, 7, 31))
