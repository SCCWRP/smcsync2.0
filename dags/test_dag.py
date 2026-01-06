from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta

def test_function():
    print("Test DAG is working!")
    return "Success"

default_args = {
    'owner': 'airflow',
    'start_date': datetime(2026, 1, 10),
}

with DAG(
    'test_simple_dag',
    default_args=default_args,
    description='Simple test DAG',
    schedule_interval=None,
    catchup=False,
) as dag:
    
    test_task = PythonOperator(
        task_id='test_task',
        python_callable=test_function,
    )
