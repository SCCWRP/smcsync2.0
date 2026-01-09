import requests
from bs4 import BeautifulSoup

def scrape_href_from_url(target_url):
    """
    Scrapes the href attribute of the <a> tag with class 'resource-url-analytics' from the given URL.
    :param target_url: The URL to scrape.
    :return: The href attribute if found, otherwise None.
    """
    try:
        response = requests.get(target_url)
        response.raise_for_status()
        
        soup = BeautifulSoup(response.text, 'html.parser')
        link = soup.find('a', class_='resource-url-analytics')
        
        if link and 'href' in link.attrs:
            return link['href']
        else:
            print("No link with the specified class found.")
            return None
    except requests.RequestException as e:
        print(f"Error during request: {e}")
        return None