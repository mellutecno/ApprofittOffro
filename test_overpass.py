import json
import urllib.request

def debug_casorate_primo():
    lat = 45.3155
    lon = 9.0165
    radius = 2000 # 2km around Casorate Primo
    
    # Query very broadly for ANYTHING with a name
    query = f"""
        [out:json][timeout:25];
        (
          nwr["amenity"~"^(restaurant|cafe|bar|pub|fast_food|ice_cream|pizzeria|food)$"](around:{radius},{lat},{lon});
          nwr["shop"~"^(bakery|pastry|deli|food|convenience|deli|pizza)$"](around:{radius},{lat},{lon});
          nwr["cuisine"](around:{radius},{lat},{lon});
        );
        out center;
    """
    
    url = 'https://overpass-api.de/api/interpreter'
    req = urllib.request.Request(url, data=query.encode('utf-8'), method='POST')
    
    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            print(f"Trovati {len(data['elements'])} elementi totali con nuovi tag food/shop.")
            
            for el in data['elements']:
                tags = el.get('tags', {})
                name = tags.get('name', 'Senza nome')
                amenity = tags.get('amenity', '')
                shop = tags.get('shop', '')
                cuisine = tags.get('cuisine', '')
                if name != 'Senza nome':
                    print(f"- {name} (amenity={amenity}, shop={shop}, cuisine={cuisine})")
    except Exception as e:
        print("Errore:", e)

if __name__ == "__main__":
    debug_casorate_primo()
