// =============================================================================
// PRUEBA TÉCNICA DBA - MÓDULO 2.2: MODELADO NO SQL PARA CATÁLOGO DE PRODUCTOS
// Base de Datos: marketplace | Colección: products
// Entorno: Producción
// =============================================================================

const db = db.getSiblingDB('marketplace');

//-- -----------------------------------------------------------------------------
//-- T1: DISEÑO DEL DOCUMENTO (Patrón de Atributos Polimórficos)
//-- -----------------------------------------------------------------------------

// Ejemplo de inserción de un producto aplicando las mejores prácticas NoSQL
db.products.insertOne({
  "sku": "PROD-CLOTH-001",
  "name": "Chaqueta Impermeable Pro",
  "description": "Chaqueta térmica ideal para exteriores",
  "price": 125.50,
  "category_id": ObjectId("60c72b2f9b1d8b23456789ab"), // Referencing para Categorías
  
  // PATRÓN DE ATRIBUTOS POLIMÓRFICOS: Optimiza índices combinados para campos variables
  "attributes": [
    { "k": "talla", "v": "L" },
    { "k": "color", "v": "Negro" },
    { "k": "material", "v": "Gore-Tex" }
  ],
  
  // Patrón de Variantes por Embedded (Subdocumentos de ciclo de vida atómico)
  "variants": [
    { "sku_suffix": "L-N", "stock": 45, "price_modifier": 0.00 },
    { "sku_suffix": "XL-N", "stock": 12, "price_modifier": 10.00 }
  ],
  
  // Reseñas mediante Referencing Externo (evita violación del límite de 16MB por documento)
  "recent_rating_summary": {
    "average_rating": 4.7,
    "total_reviews": 1540
  },
  "created_at": ISODate("2026-09-15T00:00:00Z")
});

// -- -----------------------------------------------------------------------------
// T2: ESTRATEGIA DE ÍNDICES Y ESTIMACIÓN DE TAMAÑO
// -----------------------------------------------------------------------------

// 1. Índice Compuesto Principal para el patrón de consulta más frecuente:
// Búsqueda por categoría + Filtro por atributos + Ordenamiento por precio
db.products.createIndex(
  { 
    "category_id": 1, 
    "attributes.k": 1, 
    "attributes.v": 1, 
    "price": 1 
  },
  { name: "idx_category_attributes_price" }
);

// 2. Índice Wildcard como alternativa defensiva para atributos dinámicos no estructurados
db.products.createIndex(
  { "attributes.$**": 1 },
  { name: "idx_wildcard_attributes" }
);

/*
  ESTIMACIÓN DE TAMAÑO DEL ÍNDICE PRINCIPAL:
  - Total de documentos (N): 2,000,000
  - Tamaño estimado por entrada de índice compuesto:
    * ObjectId (category_id): 12 bytes
    * String Promedio (attributes.k): ~15 bytes
    * String/Number Promedio (attributes.v): ~15 bytes
    * Double (price): 8 bytes
    * Overhead de estructura B-Tree (WireTiger): ~32 bytes
  - Total por entrada: ~82 bytes
  - Cálculo total: 2,000,000 * 82 bytes = 164,000,000 bytes (~156 MB).
  - En producción, este índice cabe perfectamente en la memoria RAM (WiredTiger Cache).
*/

// -----------------------------------------------------------------------------
// T3: AGGREGATION PIPELINE - TOP 10 MÁS VENDIDOS POR CATEGORÍA
// -----------------------------------------------------------------------------

db.orders.aggregate([
  // 1. Filtrar órdenes en la ventana crítica de producción (Últimos 30 días)
  {
    $match: {
      "purchase_date": { 
        $gte: new ISODate(new Date(new Date() - 30 * 24 * 60 * 60 * 1000).toISOString()) 
      }
    }
  },
  
  // 2. Desestructurar el array de ítems comprados
  { $unwind: "$items" },
  
  // 3. Agrupar por producto para totalizar la cantidad vendida
  {
    $group: {
      "_id": "$items.product_id",
      "total_sold": { $sum: "$items.quantity" }
    }
  },
  
  // 4. Realizar un Join con la colección de productos para traer categoría y metadatos
  {
    $lookup: {
      from: "products",
      localField: "_id",
      foreignField: "_id",
      as: "product_info"
    }
  },
  { $unwind: "$product_info" },
  
  // 5. Re-agrupar por categoría para estructurar el Top 10 interno
  {
    $group: {
      "_id": "$product_info.category_id",
      "top_products": {
        $push: {
          "product_id": "$_id",
          "name": "$product_info.name",
          "total_sold": "$total_sold",
          "average_rating": "$product_info.recent_rating_summary.average_rating"
        }
      }
    }
  },
  
  // 6. Ordenar internamente los productos de cada categoría descendentemente por volumen de ventas
  {
    $project: {
      "category_id": "$_id",
      "_id": 0,
      "top_products": {
        $slice: [
          {
            $sortArray: {
              input: "$top_products",
              sortBy: { "total_sold": -1 }
            }
          },
          10 // Limitar estrictamente al Top 10
        ]
      }
    }
  }
]);
